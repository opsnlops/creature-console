#if os(macOS) || os(tvOS)
    import Common
    import Foundation
    import Network

    enum SpatialLiveBufferPolicy {
        static func targetQueuedFrames(
            requestedDelayFrames: Int,
            renderQuantumFrames: Int
        ) -> Int {
            max(
                requestedDelayFrames,
                renderQuantumFrames + Int(RTPAudioConstants.framesPerPacket)
            )
        }
    }

    enum SpatialRTCPPreroll {
        static func frameCount(
            until enqueueDeadline: ContinuousClock.Instant,
            now: ContinuousClock.Instant,
            sampleRate: UInt32 = RTPAudioConstants.sampleRate
        ) -> Int {
            let duration = now.duration(to: enqueueDeadline)
            let components = duration.components
            let seconds =
                Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
            guard seconds > 0 else {
                return 0
            }
            let frames = ceil(seconds * Double(sampleRate))
            return frames < Double(Int.max) ? Int(frames) : Int.max
        }
    }

    enum SpatialRTCPDelayPolicy {
        static func effectivePlayoutDelay(
            configured: Duration,
            outputLatency: TimeInterval
        ) -> Duration {
            max(
                configured,
                .seconds(max(outputLatency, 0))
                    + .milliseconds(Int64(RTPAudioConstants.packetDurationMilliseconds))
            )
        }
    }

    enum SpatialRTCPReportValidation {
        static func reportsAreCompatible(
            background: TimedRTCPSenderReport,
            creatures: [TimedRTCPSenderReport],
            expectedCreatureCount: Int,
            now: ContinuousClock.Instant
        ) -> Bool {
            guard creatures.count == expectedCreatureCount,
                background.isFresh(at: now),
                creatures.allSatisfy({ $0.isFresh(at: now) })
            else {
                return false
            }

            let reports = [background.report] + creatures.map(\.report)
            guard let first = reports.first else {
                return false
            }
            return reports.dropFirst().allSatisfy {
                RTCPAudioTiming.mappingsAreCompatible(first, $0)
            }
        }
    }

    final class SpatialLiveAudioSource: @unchecked Sendable {
        private final class StreamState {
            var jitterBuffer = RTPAudioJitterBuffer()
            let decoder: SpatialOpusDecoder
            var diagnostics: SpatialChannelDiagnostics
            var senderReports = RTCPReportCache()
            var packetArrivalTimes: [UInt32: ContinuousClock.Instant] = [:]

            init(channel: Int) throws {
                decoder = try SpatialOpusDecoder()
                diagnostics = SpatialChannelDiagnostics(channel: channel)
            }

            func resetForNewSource() throws {
                try decoder.reset()
                packetArrivalTimes.removeAll(keepingCapacity: true)
            }

            func recordArrival(
                for timestamp: UInt32,
                at instant: ContinuousClock.Instant
            ) {
                packetArrivalTimes[timestamp] = packetArrivalTimes[timestamp] ?? instant
                if packetArrivalTimes.count > 64 {
                    let oldest = packetArrivalTimes.min { first, second in
                        first.value < second.value
                    }?.key
                    if let oldest {
                        packetArrivalTimes.removeValue(forKey: oldest)
                    }
                }
            }
        }

        private enum GenerationTiming {
            case waiting
            case rtcp(planner: RTCPPlayoutPlanner, report: RTCPSenderReport)
            case arrivalFallback
        }

        private let queue = DispatchQueue(
            label: "io.opsnlops.CreatureConsole.SpatialLiveAudioSource",
            qos: .userInteractive
        )
        private let renderer: SpatialAudioRenderer
        #if os(macOS)
            private let multicastReceiver = SpatialMulticastReceiver()
        #endif
        private let relayReceiver = SpatialRelayReceiver()
        private let activeChannels: Set<Int>
        private let monitoringDelayFrames: Int
        private let commonPlayoutDelay: Duration
        private let onDiagnostics: @Sendable (SpatialStageDiagnostics) -> Void
        private var streams: [Int: StreamState] = [:]
        private var timer: DispatchSourceTimer?
        private var nextTimestamp: UInt32?
        private var generationTiming = GenerationTiming.waiting
        private var initialRTCPPlan: RTCPPlayoutPlan?
        private var diagnostics = SpatialStageDiagnostics()
        private var lastDiagnosticsDate = Date.distantPast
        private var isRunning = false

        init(
            renderer: SpatialAudioRenderer,
            channels: Set<Int>,
            monitoringDelayMilliseconds: Int,
            commonPlayoutDelayMilliseconds: Int,
            onDiagnostics: @escaping @Sendable (SpatialStageDiagnostics) -> Void
        ) throws {
            self.renderer = renderer
            self.activeChannels = channels.filter { (1...16).contains($0) }
            self.monitoringDelayFrames =
                Int(RTPAudioConstants.sampleRate) * max(monitoringDelayMilliseconds, 10) / 1_000
            self.commonPlayoutDelay = .milliseconds(
                max(commonPlayoutDelayMilliseconds, 20)
            )
            self.onDiagnostics = onDiagnostics

            for channel in activeChannels.union([17]) {
                streams[channel] = try StreamState(channel: channel)
            }
            diagnostics.channels = streams.values.map(\.diagnostics).sorted {
                $0.channel < $1.channel
            }
        }

        func start(transport: SpatialLiveTransport) throws {
            queue.sync {
                stopLocked(finalState: .stopped)
                diagnostics = SpatialStageDiagnostics(state: .starting)
                diagnostics.liveTimingMode = .waiting
                lastDiagnosticsDate = .distantPast
                nextTimestamp = nil
                generationTiming = .waiting
                initialRTCPPlan = nil
                isRunning = true
                publishDiagnostics(force: true)

                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(
                    deadline: .now(),
                    repeating: .milliseconds(2),
                    leeway: .milliseconds(1)
                )
                timer.setEventHandler { [weak self] in
                    self?.fillRenderer()
                }
                timer.resume()
                self.timer = timer
            }

            let onPacket: @Sendable (SpatialReceivedPacket) -> Void = { [weak self] packet in
                guard let self else {
                    return
                }
                queue.async { [weak self] in
                    self?.receive(packet)
                }
            }
            let onError: @Sendable (String) -> Void = { [weak self] message in
                guard let self else {
                    return
                }
                queue.async { [weak self] in
                    self?.fail(message)
                }
            }

            do {
                switch transport {
                #if os(macOS)
                    case .multicast(let interface):
                        try multicastReceiver.start(
                            channels: activeChannels,
                            interface: interface,
                            onPacket: onPacket,
                            onError: onError
                        )
                #endif
                case .relay(let host, let port):
                    relayReceiver.start(
                        host: host,
                        port: port,
                        channels: activeChannels,
                        onPacket: onPacket,
                        onError: onError
                    )
                }
            } catch {
                queue.sync {
                    stopLocked(finalState: .failed(error.localizedDescription))
                    publishDiagnostics(force: true)
                }
                throw error
            }

            queue.sync {
                guard isRunning else {
                    return
                }
                if diagnostics.state == .starting {
                    diagnostics.state = .waitingForAudio
                }
                publishDiagnostics(force: true)
            }
        }

        func stop() {
            queue.sync {
                stopLocked(finalState: .stopped)
                publishDiagnostics(force: true)
            }
            stopReceivers()
            renderer.pause()
        }

        private func stopLocked(finalState: SpatialStageConnectionState) {
            isRunning = false
            timer?.cancel()
            timer = nil
            nextTimestamp = nil
            generationTiming = .waiting
            initialRTCPPlan = nil
            diagnostics.state = finalState
        }

        private func receive(_ received: SpatialReceivedPacket) {
            guard isRunning, let stream = streams[received.channel] else {
                return
            }

            switch received.kind {
            case .rtp:
                guard let packet = OpusRTPParser.parse(received.data) else {
                    stream.diagnostics.invalidPackets += 1
                    return
                }

                let insertResult = stream.jitterBuffer.insert(packet)
                if insertResult == .newSynchronizationSource {
                    do {
                        try stream.resetForNewSource()
                    } catch {
                        fail("Unable to reset the Opus decoder: \(error.localizedDescription)")
                        return
                    }
                    if received.channel == 17, !restartTimeline() {
                        return
                    }
                }
                if insertResult == .inserted || insertResult == .newSynchronizationSource {
                    stream.recordArrival(for: packet.timestamp, at: .now)
                    stream.diagnostics.packetsReceived += 1
                    stream.diagnostics.lastPacketDate = Date()
                }
                updateRTCPValidity(at: .now)

            case .rtcp:
                guard let report = RTCPSenderReportParser.parse(received.data) else {
                    return
                }
                stream.senderReports.store(report, receivedAt: .now)
                diagnostics.rtcpReportsReceived += 1
                updateRTCPValidity(at: .now)
            }
        }

        @discardableResult
        private func restartTimeline() -> Bool {
            nextTimestamp = nil
            generationTiming = .waiting
            initialRTCPPlan = nil
            diagnostics.state = .waitingForAudio
            diagnostics.liveTimingMode = .waiting
            diagnostics.rtcpStartLatenessMilliseconds = nil
            diagnostics.rtcpPlayoutDelayMilliseconds = nil
            diagnostics.rtcpLateFramesDropped = 0
            do {
                try renderer.reset(leadFrames: 0)
                return true
            } catch {
                fail("Audio output failed to restart: \(error.localizedDescription)")
                return false
            }
        }

        private func stopReceivers() {
            #if os(macOS)
                multicastReceiver.stop()
            #endif
            relayReceiver.stop()
        }

        private func fail(_ message: String) {
            guard isRunning else {
                return
            }
            stopLocked(finalState: .failed(message))
            stopReceivers()
            renderer.pause()
            publishDiagnostics(force: true)
        }

        private func fillRenderer() {
            guard isRunning, let background = streams[17] else {
                return
            }

            if nextTimestamp == nil {
                startTimelineIfReady(background: background, now: .now)
            }

            guard var timestamp = nextTimestamp else {
                publishDiagnostics()
                return
            }

            let targetQueuedFrames = SpatialLiveBufferPolicy.targetQueuedFrames(
                requestedDelayFrames: monitoringDelayFrames,
                renderQuantumFrames: renderer.renderQuantumFrames
            )
            while renderer.queuedFrames < targetQueuedFrames {
                let nextPacketTimestamp = timestamp &+ RTPAudioConstants.framesPerPacket
                let backgroundPacket = background.jitterBuffer.takePacket(at: timestamp)
                let backgroundFEC = background.jitterBuffer.packet(at: nextPacketTimestamp)

                if backgroundPacket == nil, backgroundFEC == nil,
                    !background.jitterBuffer.hasPacket(after: timestamp)
                {
                    break
                }

                let backgroundDecoded = background.decoder.decode(
                    payload: backgroundPacket?.payload,
                    forwardErrorCorrectionPayload: backgroundFEC?.payload
                )
                record(backgroundDecoded, for: background)

                var creatureSamples: [Int: [Float]] = [:]
                for channel in activeChannels {
                    guard let stream = streams[channel] else {
                        continue
                    }
                    stream.jitterBuffer.discard(before: timestamp)
                    let packet = stream.jitterBuffer.takePacket(at: timestamp)
                    let fecPacket = stream.jitterBuffer.packet(at: nextPacketTimestamp)
                    let decoded = stream.decoder.decode(
                        payload: packet?.payload,
                        forwardErrorCorrectionPayload: fecPacket?.payload
                    )
                    record(decoded, for: stream)
                    creatureSamples[channel] = decoded.samples
                    stream.packetArrivalTimes.removeValue(forKey: timestamp)
                }

                let queuedFramesBeforeEnqueue = renderer.queuedFrames
                guard
                    renderer.enqueue(
                        creatureSamples: creatureSamples,
                        backgroundSamples: backgroundDecoded.samples,
                        frameCount: Int(RTPAudioConstants.framesPerPacket)
                    )
                else {
                    fail("The spatial audio output queue could not accept a complete frame.")
                    return
                }

                if let initialRTCPPlan {
                    let predictedPresentation = ContinuousClock.now.advanced(
                        by: .seconds(
                            Double(queuedFramesBeforeEnqueue)
                                / Double(RTPAudioConstants.sampleRate)
                                + renderer.outputPresentationLatency
                        )
                    )
                    diagnostics.rtcpStartLatenessMilliseconds =
                        durationSeconds(
                            initialRTCPPlan.presentationDeadline.duration(
                                to: predictedPresentation
                            )
                        ) * 1_000
                    self.initialRTCPPlan = nil
                }

                background.packetArrivalTimes.removeValue(forKey: timestamp)
                timestamp = nextPacketTimestamp
                nextTimestamp = nextPacketTimestamp
            }

            publishDiagnostics()
        }

        private func startTimelineIfReady(
            background: StreamState,
            now: ContinuousClock.Instant
        ) {
            guard let timestamp = background.jitterBuffer.earliestTimestamp(),
                let arrival = background.packetArrivalTimes[timestamp]
            else {
                return
            }

            if case .waiting = generationTiming {
                chooseTimingMode(
                    backgroundTimestamp: timestamp,
                    arrival: arrival,
                    now: now
                )
            }

            switch generationTiming {
            case .waiting:
                return

            case .rtcp(let planner, let report):
                guard
                    let plan = planner.plan(
                        report: report,
                        rtpTimestamp: timestamp,
                        queuedFrames: 0
                    )
                else {
                    generationTiming = .arrivalFallback
                    diagnostics.liveTimingMode = .arrivalFallback
                    startTimelineIfReady(background: background, now: now)
                    return
                }

                if RTCPAudioTiming.classifyEnqueue(plan, now: now) == .missed {
                    discardTimestamp(timestamp)
                    diagnostics.rtcpLateFramesDropped += 1
                    return
                }

                let leadFrames = SpatialRTCPPreroll.frameCount(
                    until: plan.enqueueDeadline,
                    now: now
                )
                do {
                    try renderer.reset(leadFrames: leadFrames)
                } catch {
                    fail("Audio output failed to start: \(error.localizedDescription)")
                    return
                }
                initialRTCPPlan = plan

            case .arrivalFallback:
                // A 512-frame Core Audio pull spans more than one 480-frame RTP packet.
                // Keep two packets available before fallback starts so the first callback
                // cannot insert a silent tail and stretch the stream.
                guard background.jitterBuffer.packetCount >= 2 else {
                    return
                }
                let fallbackEnqueueDeadline = arrival.advanced(
                    by: .seconds(
                        Double(monitoringDelayFrames) / Double(RTPAudioConstants.sampleRate)
                    )
                )
                let leadFrames = SpatialRTCPPreroll.frameCount(
                    until: fallbackEnqueueDeadline,
                    now: now
                )
                do {
                    try renderer.reset(leadFrames: leadFrames)
                } catch {
                    fail("Audio output failed to start: \(error.localizedDescription)")
                    return
                }
            }

            nextTimestamp = timestamp
            diagnostics.state = .playing
        }

        private func chooseTimingMode(
            backgroundTimestamp: UInt32,
            arrival: ContinuousClock.Instant,
            now: ContinuousClock.Instant
        ) {
            if let backgroundReport = compatibleBackgroundReport(at: now) {
                let outputLatency = renderer.outputPresentationLatency
                let effectivePlayoutDelay = SpatialRTCPDelayPolicy.effectivePlayoutDelay(
                    configured: commonPlayoutDelay,
                    outputLatency: outputLatency
                )
                let planner = RTCPPlayoutPlanner(
                    clockPair: .capture(),
                    commonPlayoutDelay: effectivePlayoutDelay,
                    outputLatency: .seconds(outputLatency)
                )
                if let plan = planner.plan(
                    report: backgroundReport.report,
                    rtpTimestamp: backgroundTimestamp,
                    queuedFrames: 0
                ),
                    RTCPAudioTiming.presentationDeadlineIsPlausible(
                        plan,
                        packetArrival: arrival,
                        commonPlayoutDelay: effectivePlayoutDelay
                    )
                {
                    generationTiming = .rtcp(
                        planner: planner,
                        report: backgroundReport.report
                    )
                    diagnostics.liveTimingMode = .rtcp
                    diagnostics.rtcpPlayoutDelayMilliseconds =
                        durationSeconds(effectivePlayoutDelay) * 1_000
                    return
                }
            }

            guard
                arrival.duration(to: now)
                    >= .milliseconds(10)
            else {
                return
            }
            generationTiming = .arrivalFallback
            diagnostics.liveTimingMode = .arrivalFallback
        }

        private func discardTimestamp(_ timestamp: UInt32) {
            let followingTimestamp = timestamp &+ RTPAudioConstants.framesPerPacket
            for stream in streams.values {
                stream.jitterBuffer.discard(before: followingTimestamp)
                stream.packetArrivalTimes.removeValue(forKey: timestamp)
            }
        }

        private func compatibleBackgroundReport(
            at now: ContinuousClock.Instant
        ) -> TimedRTCPSenderReport? {
            guard let background = streams[17],
                let backgroundSource = background.jitterBuffer.synchronizationSource,
                let backgroundReport = background.senderReports.report(for: backgroundSource),
                backgroundReport.isFresh(at: now)
            else {
                return nil
            }

            var creatureReports: [TimedRTCPSenderReport] = []
            creatureReports.reserveCapacity(activeChannels.count)
            for channel in activeChannels.sorted() {
                guard let stream = streams[channel],
                    let source = stream.jitterBuffer.synchronizationSource,
                    let report = stream.senderReports.report(for: source)
                else {
                    return nil
                }
                creatureReports.append(report)
            }

            guard
                SpatialRTCPReportValidation.reportsAreCompatible(
                    background: backgroundReport,
                    creatures: creatureReports,
                    expectedCreatureCount: activeChannels.count,
                    now: now
                )
            else {
                return nil
            }
            return backgroundReport
        }

        private func updateRTCPValidity(at now: ContinuousClock.Instant) {
            diagnostics.rtcpClockValid = compatibleBackgroundReport(at: now) != nil
        }

        private func record(
            _ decoded: (samples: [Float], kind: SpatialOpusDecoder.DecodeKind),
            for stream: StreamState
        ) {
            switch decoded.kind {
            case .forwardErrorCorrection:
                stream.diagnostics.fecFrames += 1
            case .packetLossConcealment, .silence:
                stream.diagnostics.concealedFrames += 1
            case .packet:
                break
            }
            let rootMeanSquare = SpatialAudioLevel.rootMeanSquare(of: decoded.samples)
            stream.diagnostics.level = max(rootMeanSquare, stream.diagnostics.level * 0.82)
        }

        private func publishDiagnostics(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastDiagnosticsDate) >= 0.1 else {
                return
            }
            lastDiagnosticsDate = now
            diagnostics.bufferedMilliseconds =
                Double(renderer.queuedFrames) / Double(RTPAudioConstants.sampleRate) * 1_000
            diagnostics.outputLatencyMilliseconds = renderer.outputPresentationLatency * 1_000
            diagnostics.outputUnderruns = renderer.outputUnderruns
            if isRunning {
                updateRTCPValidity(at: .now)
            }
            diagnostics.channels = streams.values.map(\.diagnostics).sorted {
                $0.channel < $1.channel
            }
            onDiagnostics(diagnostics)
        }

        private func durationSeconds(_ duration: Duration) -> TimeInterval {
            let components = duration.components
            return Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
        }
    }
#endif

#if os(macOS)
    import Common
    import Foundation
    import Network

    final class SpatialLiveAudioSource: @unchecked Sendable {
        private final class StreamState {
            var jitterBuffer = RTPAudioJitterBuffer()
            let decoder: SpatialOpusDecoder
            var diagnostics: SpatialChannelDiagnostics
            var senderReport: RTCPSenderReport?

            init(channel: Int) throws {
                decoder = try SpatialOpusDecoder()
                diagnostics = SpatialChannelDiagnostics(channel: channel)
            }
        }

        private let queue = DispatchQueue(
            label: "io.opsnlops.CreatureConsole.SpatialLiveAudioSource",
            qos: .userInteractive
        )
        private let renderer: SpatialAudioRenderer
        private let receiver = SpatialMulticastReceiver()
        private let activeChannels: Set<Int>
        private let monitoringDelayFrames: Int
        private let onDiagnostics: @Sendable (SpatialStageDiagnostics) -> Void
        private var streams: [Int: StreamState] = [:]
        private var timer: DispatchSourceTimer?
        private var nextTimestamp: UInt32?
        private var diagnostics = SpatialStageDiagnostics()
        private var lastDiagnosticsDate = Date.distantPast
        private var isRunning = false

        init(
            renderer: SpatialAudioRenderer,
            channels: Set<Int>,
            monitoringDelayMilliseconds: Int,
            onDiagnostics: @escaping @Sendable (SpatialStageDiagnostics) -> Void
        ) throws {
            self.renderer = renderer
            self.activeChannels = channels.filter { (1...16).contains($0) }
            self.monitoringDelayFrames =
                Int(RTPAudioConstants.sampleRate) * max(monitoringDelayMilliseconds, 10) / 1_000
            self.onDiagnostics = onDiagnostics

            for channel in activeChannels.union([17]) {
                streams[channel] = try StreamState(channel: channel)
            }
            diagnostics.channels = streams.values.map(\.diagnostics).sorted {
                $0.channel < $1.channel
            }
        }

        func start(interface: NWInterface) throws {
            diagnostics.state = .starting
            publishDiagnostics(force: true)
            isRunning = true

            try receiver.start(
                channels: activeChannels,
                interface: interface
            ) { [weak self] packet in
                guard let self else {
                    return
                }
                queue.async { [self] in
                    receive(packet)
                }
            } onError: { [weak self] message in
                guard let self else {
                    return
                }
                queue.async { [self] in
                    fail(message)
                }
            }

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                self?.fillRenderer()
            }
            self.timer = timer
            timer.resume()
            diagnostics.state = .waitingForAudio
            publishDiagnostics(force: true)
        }

        func stop() {
            receiver.stop()
            queue.async { [weak self] in
                guard let self else {
                    return
                }
                isRunning = false
                timer?.cancel()
                timer = nil
                nextTimestamp = nil
                diagnostics.state = .stopped
                publishDiagnostics(force: true)
            }
        }

        private func receive(_ received: SpatialMulticastReceiver.ReceivedPacket) {
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
                    try? stream.decoder.reset()
                    if received.channel == 17 {
                        restartTimeline()
                    }
                }
                if insertResult == .inserted || insertResult == .newSynchronizationSource {
                    stream.diagnostics.packetsReceived += 1
                    stream.diagnostics.lastPacketDate = Date()
                }
            case .rtcp:
                guard let report = RTCPSenderReportParser.parse(received.data) else {
                    return
                }
                stream.senderReport = report
                diagnostics.rtcpReportsReceived += 1
                updateRTCPValidity()
            }
        }

        private func restartTimeline() {
            nextTimestamp = nil
            renderer.reset(leadFrames: Int(RTPAudioConstants.framesPerPacket))
            diagnostics.state = .waitingForAudio
        }

        private func fail(_ message: String) {
            guard isRunning else {
                return
            }
            isRunning = false
            timer?.cancel()
            timer = nil
            diagnostics.state = .failed(message)
            publishDiagnostics(force: true)
        }

        private func fillRenderer() {
            guard isRunning, let background = streams[17] else {
                return
            }

            if nextTimestamp == nil {
                let requiredPackets =
                    monitoringDelayFrames / Int(RTPAudioConstants.framesPerPacket)
                guard
                    background.jitterBuffer.packetCount >= requiredPackets,
                    let firstTimestamp = background.jitterBuffer.earliestTimestamp()
                else {
                    publishDiagnostics()
                    return
                }
                nextTimestamp = firstTimestamp
                renderer.reset(leadFrames: Int(RTPAudioConstants.framesPerPacket))
                diagnostics.state = .playing
            }

            while renderer.queuedFrames < monitoringDelayFrames {
                guard let timestamp = nextTimestamp else {
                    break
                }
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
                }

                guard
                    renderer.enqueue(
                        creatureSamples: creatureSamples,
                        backgroundSamples: backgroundDecoded.samples,
                        frameCount: Int(RTPAudioConstants.framesPerPacket)
                    )
                else {
                    break
                }
                nextTimestamp = nextPacketTimestamp
            }

            diagnostics.bufferedMilliseconds =
                Double(renderer.queuedFrames) / Double(RTPAudioConstants.sampleRate) * 1_000
            diagnostics.outputLatencyMilliseconds = renderer.outputPresentationLatency * 1_000
            publishDiagnostics()
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

        private func updateRTCPValidity() {
            guard let backgroundReport = streams[17]?.senderReport else {
                diagnostics.rtcpClockValid = false
                return
            }
            let availableReports = activeChannels.compactMap { streams[$0]?.senderReport }
            diagnostics.rtcpClockValid =
                !availableReports.isEmpty
                && availableReports.allSatisfy {
                    RTCPAudioTiming.mappingsAreCompatible(backgroundReport, $0)
                }
        }

        private func publishDiagnostics(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastDiagnosticsDate) >= 0.1 else {
                return
            }
            lastDiagnosticsDate = now
            diagnostics.channels = streams.values.map(\.diagnostics).sorted {
                $0.channel < $1.channel
            }
            onDiagnostics(diagnostics)
        }
    }
#endif

#if os(macOS) || os(tvOS)
    import AVFAudio
    import Common
    import Foundation

    protocol SpatialSimulationAudioRendering: Sendable {
        var queuedFrames: Int { get }
        var outputPresentationLatency: TimeInterval { get }

        func reset(leadFrames: Int, resumeAfterReset: Bool) throws
        func enqueue(
            creatureSamples: [Int: [Float]],
            backgroundSamples: [Float],
            frameCount: Int
        ) -> Bool
        func pause()
        func resume() throws
    }

    extension SpatialSimulationAudioRendering {
        func reset(leadFrames: Int) throws {
            try reset(leadFrames: leadFrames, resumeAfterReset: true)
        }
    }

    extension SpatialAudioRenderer: SpatialSimulationAudioRendering {}

    final class SpatialSimulationAudioSource: @unchecked Sendable {
        private let queue = DispatchQueue(
            label: "io.opsnlops.CreatureConsole.SpatialSimulationAudioSource",
            qos: .userInitiated
        )
        private let renderer: any SpatialSimulationAudioRendering
        private let file: AVAudioFile
        private let channels: Set<Int>
        private let onDiagnostics: @Sendable (SpatialStageDiagnostics) -> Void
        private let targetBufferedFrames = Int(RTPAudioConstants.sampleRate) / 4
        private var timer: DispatchSourceTimer?
        private var diagnostics = SpatialStageDiagnostics()
        private var lastDiagnosticsDate = Date.distantPast
        private var isPaused = false
        private var isLooping = false
        private var reachedEnd = false
        private var completionPauseWorkItem: DispatchWorkItem?

        init(
            renderer: any SpatialSimulationAudioRendering,
            fileURL: URL,
            channels: Set<Int>,
            onDiagnostics: @escaping @Sendable (SpatialStageDiagnostics) -> Void
        ) throws {
            self.renderer = renderer
            self.file = try AVAudioFile(
                forReading: fileURL,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            self.channels = channels.filter { (1...16).contains($0) }
            self.onDiagnostics = onDiagnostics

            guard file.processingFormat.channelCount == 17 else {
                throw SpatialSimulationError.wrongChannelCount(
                    actual: Int(file.processingFormat.channelCount)
                )
            }
            guard
                abs(file.processingFormat.sampleRate - Double(RTPAudioConstants.sampleRate)) < 0.5
            else {
                throw SpatialSimulationError.unsupportedSampleRate(
                    actual: file.processingFormat.sampleRate
                )
            }

            diagnostics.simulationDuration =
                Double(file.length) / file.processingFormat.sampleRate
            diagnostics.channels = self.channels.union([17]).sorted().map {
                SpatialChannelDiagnostics(channel: $0)
            }
        }

        func start(looping: Bool) {
            queue.async { [weak self] in
                guard let self else {
                    return
                }
                isLooping = looping
                isPaused = false
                reachedEnd = false
                completionPauseWorkItem?.cancel()
                completionPauseWorkItem = nil
                do {
                    try renderer.reset(leadFrames: Int(RTPAudioConstants.framesPerPacket) * 2)
                } catch {
                    diagnostics.state = .failed(error.localizedDescription)
                    publishDiagnostics(force: true)
                    return
                }
                diagnostics.state = .playing
                publishDiagnostics(force: true)

                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(
                    deadline: .now(),
                    repeating: .milliseconds(5),
                    leeway: .milliseconds(1)
                )
                timer.setEventHandler { [weak self] in
                    self?.fillRenderer()
                }
                self.timer = timer
                timer.resume()
            }
        }

        func stop() {
            queue.async { [weak self] in
                guard let self else {
                    return
                }
                timer?.cancel()
                timer = nil
                completionPauseWorkItem?.cancel()
                completionPauseWorkItem = nil
                renderer.pause()
                diagnostics.state = .stopped
                publishDiagnostics(force: true)
            }
        }

        func setPaused(_ paused: Bool) {
            queue.async { [weak self] in
                guard let self, timer != nil else {
                    return
                }
                isPaused = paused
                if paused {
                    renderer.pause()
                    diagnostics.state = .paused
                } else {
                    do {
                        try renderer.resume()
                        diagnostics.state = .playing
                    } catch {
                        diagnostics.state = .failed(error.localizedDescription)
                    }
                }
                publishDiagnostics(force: true)
            }
        }

        func setLooping(_ looping: Bool) {
            queue.async { [weak self] in
                self?.isLooping = looping
            }
        }

        func seek(to time: TimeInterval) {
            queue.async { [weak self] in
                guard let self else {
                    return
                }
                let clampedTime = min(max(time, 0), diagnostics.simulationDuration)
                file.framePosition = AVAudioFramePosition(
                    clampedTime * file.processingFormat.sampleRate
                )
                reachedEnd = false
                completionPauseWorkItem?.cancel()
                completionPauseWorkItem = nil
                do {
                    try renderer.reset(
                        leadFrames: Int(RTPAudioConstants.framesPerPacket) * 2,
                        resumeAfterReset: !isPaused
                    )
                } catch {
                    timer?.cancel()
                    timer = nil
                    diagnostics.state = .failed(error.localizedDescription)
                }
                updatePosition()
                publishDiagnostics(force: true)
            }
        }

        private func fillRenderer() {
            guard !isPaused else {
                publishDiagnostics()
                return
            }

            do {
                while !reachedEnd, renderer.queuedFrames < targetBufferedFrames {
                    try enqueueNextBlock()
                }
                if reachedEnd, renderer.queuedFrames == 0 {
                    if isLooping {
                        file.framePosition = 0
                        reachedEnd = false
                        try renderer.reset(
                            leadFrames: Int(RTPAudioConstants.framesPerPacket) * 2
                        )
                    } else {
                        finishPlayback()
                        return
                    }
                }
                diagnostics.bufferedMilliseconds =
                    Double(renderer.queuedFrames) / file.processingFormat.sampleRate * 1_000
                diagnostics.outputLatencyMilliseconds =
                    renderer.outputPresentationLatency * 1_000
                updatePosition()
                publishDiagnostics()
            } catch {
                timer?.cancel()
                timer = nil
                diagnostics.state = .failed(error.localizedDescription)
                publishDiagnostics(force: true)
            }
        }

        private func finishPlayback() {
            timer?.cancel()
            timer = nil
            diagnostics.state = .stopped
            diagnostics.bufferedMilliseconds = 0
            diagnostics.simulationPosition = diagnostics.simulationDuration
            for index in diagnostics.channels.indices {
                diagnostics.channels[index].level = 0
            }

            // The timer will not fire again, so the terminal state must bypass the normal
            // diagnostics throttle or the UI can remain stuck in Playing.
            publishDiagnostics(force: true)

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, timer == nil, diagnostics.state == .stopped else {
                    return
                }
                renderer.pause()
                completionPauseWorkItem = nil
            }
            completionPauseWorkItem = workItem
            queue.asyncAfter(
                deadline: .now() + max(renderer.outputPresentationLatency, 0),
                execute: workItem
            )
        }

        private func enqueueNextBlock() throws {
            let requestedFrames = min(
                AVAudioFrameCount(RTPAudioConstants.framesPerPacket),
                AVAudioFrameCount(max(file.length - file.framePosition, 0))
            )
            guard requestedFrames > 0 else {
                reachedEnd = true
                return
            }
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: requestedFrames
                )
            else {
                throw SpatialSimulationError.cannotAllocateBuffer
            }

            try file.read(into: buffer, frameCount: requestedFrames)
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else {
                reachedEnd = true
                return
            }
            guard let channelData = buffer.floatChannelData else {
                throw SpatialSimulationError.unsupportedPCMFormat
            }

            var creatureSamples: [Int: [Float]] = [:]
            for channel in channels {
                let samples = Array(
                    UnsafeBufferPointer(
                        start: channelData[channel - 1],
                        count: frameCount
                    )
                )
                creatureSamples[channel] = samples
                recordLevel(samples, channel: channel)
            }
            let backgroundSamples = Array(
                UnsafeBufferPointer(start: channelData[16], count: frameCount)
            )
            recordLevel(backgroundSamples, channel: 17)
            guard
                renderer.enqueue(
                    creatureSamples: creatureSamples,
                    backgroundSamples: backgroundSamples,
                    frameCount: frameCount
                )
            else {
                throw SpatialSimulationError.rendererQueueFull
            }
        }

        private func updatePosition() {
            let audibleFrame = max(
                file.framePosition - AVAudioFramePosition(renderer.queuedFrames),
                0
            )
            diagnostics.simulationPosition =
                Double(audibleFrame) / file.processingFormat.sampleRate
        }

        private func recordLevel(_ samples: [Float], channel: Int) {
            guard
                let index = diagnostics.channels.firstIndex(where: { $0.channel == channel })
            else {
                return
            }
            let rootMeanSquare = SpatialAudioLevel.rootMeanSquare(of: samples)
            diagnostics.channels[index].level = max(
                rootMeanSquare,
                diagnostics.channels[index].level * 0.82
            )
        }

        private func publishDiagnostics(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastDiagnosticsDate) >= 0.1 else {
                return
            }
            lastDiagnosticsDate = now
            onDiagnostics(diagnostics)
        }
    }

    enum SpatialSimulationError: LocalizedError {
        case wrongChannelCount(actual: Int)
        case unsupportedSampleRate(actual: Double)
        case unsupportedPCMFormat
        case cannotAllocateBuffer
        case rendererQueueFull

        var errorDescription: String? {
            switch self {
            case .wrongChannelCount(let actual):
                "Simulation requires a 17-channel WAV; this file has \(actual) channels."
            case .unsupportedSampleRate(let actual):
                "Simulation requires 48 kHz audio; this file is \(Int(actual)) Hz."
            case .unsupportedPCMFormat:
                "The simulation WAV could not be converted to floating-point PCM."
            case .cannotAllocateBuffer:
                "The simulation audio buffer could not be allocated."
            case .rendererQueueFull:
                "The spatial renderer could not accept more simulation audio."
            }
        }
    }
#endif

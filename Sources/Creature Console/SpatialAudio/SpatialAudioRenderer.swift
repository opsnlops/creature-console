#if os(macOS)
    import AVFAudio
    import Common
    import Foundation

    final class SpatialAudioRenderer: @unchecked Sendable {
        private static let queueCapacityFrames = Int(RTPAudioConstants.sampleRate) * 3

        private struct Emitter {
            let queue: SpatialPCMQueue
            let sourceNode: AVAudioSourceNode
        }

        private let engine = AVAudioEngine()
        private let environment = AVAudioEnvironmentNode()
        private let backgroundQueue = SpatialPCMQueue(capacity: queueCapacityFrames)
        private let backgroundNode: AVAudioSourceNode
        private var emitters: [Int: Emitter] = [:]
        private let format: AVAudioFormat

        init(channels: Set<Int>) throws {
            guard
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: Double(RTPAudioConstants.sampleRate),
                    channels: 1,
                    interleaved: false
                )
            else {
                throw SpatialAudioRendererError.cannotCreateFormat
            }
            self.format = format
            self.backgroundNode = Self.makeSourceNode(
                format: format,
                queue: backgroundQueue
            )

            engine.attach(environment)
            engine.attach(backgroundNode)
            engine.connect(backgroundNode, to: engine.mainMixerNode, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)

            environment.outputType = .auto
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 1.6, z: 2)
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
                yaw: 0,
                pitch: 0,
                roll: 0
            )
            environment.reverbParameters.enable = true
            environment.reverbParameters.loadFactoryReverbPreset(.mediumHall)
            environment.reverbParameters.level = -12

            for channel in channels.sorted() where (1...16).contains(channel) {
                let queue = SpatialPCMQueue(capacity: Self.queueCapacityFrames)
                let sourceNode = Self.makeSourceNode(format: format, queue: queue)
                engine.attach(sourceNode)
                engine.connect(
                    sourceNode,
                    to: environment,
                    fromBus: 0,
                    toBus: environment.nextAvailableInputBus,
                    format: format
                )
                sourceNode.sourceMode = .pointSource
                sourceNode.renderingAlgorithm = .auto
                sourceNode.reverbBlend = 0.08
                emitters[channel] = Emitter(queue: queue, sourceNode: sourceNode)
            }

            engine.prepare()
            try engine.start()
        }

        deinit {
            engine.stop()
        }

        var queuedFrames: Int {
            let queues = emitters.values.map(\.queue.availableFrames)
            return ([backgroundQueue.availableFrames] + queues).min() ?? 0
        }

        var outputPresentationLatency: TimeInterval {
            environment.outputPresentationLatency
        }

        func reset(leadFrames: Int, resumeAfterReset: Bool = true) {
            engine.pause()
            backgroundQueue.clearAndPrime(silenceFrames: leadFrames)
            for emitter in emitters.values {
                emitter.queue.clearAndPrime(silenceFrames: leadFrames)
            }
            if resumeAfterReset {
                try? engine.start()
            }
        }

        @discardableResult
        func enqueue(
            creatureSamples: [Int: [Float]],
            backgroundSamples: [Float],
            frameCount: Int
        ) -> Bool {
            guard backgroundSamples.count == frameCount else {
                return false
            }

            var success = backgroundQueue.write(backgroundSamples)
            let silence = [Float](repeating: 0, count: frameCount)
            for (channel, emitter) in emitters {
                let samples = creatureSamples[channel] ?? silence
                guard samples.count == frameCount else {
                    success = false
                    continue
                }
                success = emitter.queue.write(samples) && success
            }
            return success
        }

        func update(layout: SpatialStageLayout) {
            environment.listenerPosition = AVAudio3DPoint(
                x: layout.listenerX,
                y: layout.listenerY,
                z: layout.listenerZ
            )
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
                yaw: layout.listenerYaw,
                pitch: 0,
                roll: 0
            )
            backgroundNode.volume = layout.backgroundMusicGain

            for placement in layout.placements {
                guard let emitter = emitters[placement.audioChannel] else {
                    continue
                }
                emitter.sourceNode.position = AVAudio3DPoint(
                    x: placement.x,
                    y: placement.y,
                    z: placement.z
                )
                emitter.sourceNode.volume = placement.isMuted ? 0 : placement.gain
                emitter.sourceNode.reverbBlend = layout.reverbBlend
            }
        }

        func setMasterVolume(_ volume: Float) {
            engine.mainMixerNode.outputVolume = min(max(volume, 0), 1)
        }

        func pause() {
            engine.pause()
        }

        func resume() throws {
            guard !engine.isRunning else {
                return
            }
            try engine.start()
        }

        private static func makeSourceNode(
            format: AVAudioFormat,
            queue: SpatialPCMQueue
        ) -> AVAudioSourceNode {
            AVAudioSourceNode(format: format) { isSilence, _, frameCount, outputData in
                let buffers = UnsafeMutableAudioBufferListPointer(outputData)
                guard
                    let audioBuffer = buffers.first,
                    let data = audioBuffer.mData?.assumingMemoryBound(to: Float.self)
                else {
                    isSilence.pointee = true
                    return noErr
                }

                isSilence.pointee = ObjCBool(
                    queue.read(
                        into: data,
                        frameCount: Int(frameCount)
                    )
                )
                return noErr
            }
        }
    }

    enum SpatialAudioRendererError: LocalizedError {
        case cannotCreateFormat

        var errorDescription: String? {
            "Unable to create the 48 kHz mono spatial audio format."
        }
    }
#endif

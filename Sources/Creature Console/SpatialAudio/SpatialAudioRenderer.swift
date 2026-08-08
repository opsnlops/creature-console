#if os(macOS) || os(tvOS)
    import AVFAudio
    import Accelerate
    import Common
    import Foundation
    import Synchronization

    final class SpatialAudioRenderer: @unchecked Sendable {
        private static let queueCapacityFrames = Int(RTPAudioConstants.sampleRate) * 3

        private final class RenderQuantumTracker: @unchecked Sendable {
            let frames = Atomic<Int>(Int(RTPAudioConstants.framesPerPacket))
        }

        private struct Emitter {
            let queue: SpatialPCMQueue
            let sourceNode: AVAudioSourceNode
        }

        /// Per-lane and music gains, applied in the *sample* domain at enqueue time.
        /// AVAudioMixing.volume silently clamps to 1.0 — a 150% stage gain set through node
        /// volume just lies. Node volume is reserved for mute (instant); magnitude lives here,
        /// where values above 1.0 are honest. Written on the main actor, read on the audio
        /// producer's queue.
        private struct GainState {
            var lanes: [Int: Float] = [:]
            var music: Float = 0.7
        }

        private let engine = AVAudioEngine()
        private let environment = AVAudioEnvironmentNode()
        /// Device-level makeup gain (dB) after the mix — multichannel speaker rendering spreads
        /// energy across the layout and lands quieter than the Mac's stereo render, and living
        /// rooms want more level than the positional math alone provides.
        private let makeupEQ = AVAudioUnitEQ(numberOfBands: 0)
        private let gainState = Mutex<GainState>(GainState())
        private let backgroundQueue = SpatialPCMQueue(capacity: queueCapacityFrames)
        private let backgroundNode: AVAudioSourceNode
        private let renderQuantumTracker: RenderQuantumTracker
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
            let renderQuantumTracker = RenderQuantumTracker()
            self.format = format
            self.renderQuantumTracker = renderQuantumTracker
            self.backgroundNode = Self.makeSourceNode(
                format: format,
                queue: backgroundQueue,
                renderQuantumTracker: renderQuantumTracker
            )

            engine.attach(environment)
            engine.attach(backgroundNode)
            engine.attach(makeupEQ)
            engine.connect(backgroundNode, to: engine.mainMixerNode, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            engine.connect(engine.mainMixerNode, to: makeupEQ, format: nil)
            engine.connect(makeupEQ, to: engine.outputNode, format: nil)

            environment.outputType = .auto
            // Stage coordinates are relative to the listener, so these ears sit at the origin.
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
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
            max(
                environment.outputPresentationLatency,
                engine.outputNode.presentationLatency
            )
        }

        var renderQuantumFrames: Int {
            renderQuantumTracker.frames.load(ordering: .relaxed)
        }

        var outputUnderruns: UInt64 {
            backgroundQueue.underruns
        }

        func reset(leadFrames: Int, resumeAfterReset: Bool = true) throws {
            engine.pause()
            backgroundQueue.clearAndPrime(silenceFrames: leadFrames)
            for emitter in emitters.values {
                emitter.queue.clearAndPrime(silenceFrames: leadFrames)
            }
            if resumeAfterReset {
                try engine.start()
            }
        }

        @discardableResult
        func enqueue(
            creatureSamples: [Int: [Float]],
            backgroundSamples: [Float],
            frameCount: Int
        ) -> Bool {
            guard
                backgroundSamples.count == frameCount,
                backgroundQueue.canWrite(frameCount: frameCount)
            else {
                return false
            }

            let silence = [Float](repeating: 0, count: frameCount)
            for (channel, emitter) in emitters {
                let samples = creatureSamples[channel] ?? silence
                guard
                    samples.count == frameCount,
                    emitter.queue.canWrite(frameCount: frameCount)
                else {
                    return false
                }
            }

            let gains = gainState.withLock { $0 }

            // There is one producer, and the consumers only increase available capacity.
            // Once every queue passes the preflight, the batch cannot partially fail.
            guard backgroundQueue.write(Self.applying(gain: gains.music, to: backgroundSamples))
            else {
                return false
            }
            for (channel, emitter) in emitters {
                let samples = Self.applying(
                    gain: gains.lanes[channel] ?? 1,
                    to: creatureSamples[channel] ?? silence
                )
                guard emitter.queue.write(samples) else {
                    assertionFailure("Spatial PCM queue capacity changed after preflight")
                    return false
                }
            }
            return true
        }

        func update(stage: Stage) {
            // The stage frame puts the listener at the origin facing -Z, so there is nothing to
            // position any more — the coordinates arrive already relative to these ears.
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
                yaw: 0,
                pitch: 0,
                roll: 0
            )
            gainState.withLock { state in
                state.music = stage.audio.backgroundMusicGain
                state.lanes = Dictionary(
                    uniqueKeysWithValues: stage.placements.map { ($0.audioChannel, $0.gain) }
                )
            }

            for placement in stage.placements {
                guard let emitter = emitters[placement.audioChannel] else {
                    continue
                }
                emitter.sourceNode.position = AVAudio3DPoint(
                    x: placement.x,
                    y: placement.y,
                    z: placement.z
                )
                // Mute stays on the node so it lands instantly; magnitude is applied to the
                // samples at enqueue time (node volume clamps at 1.0, stage gain goes to 1.5).
                emitter.sourceNode.volume = placement.isMuted ? 0 : 1
                emitter.sourceNode.reverbBlend = stage.audio.reverbBlend
            }
        }

        /// Post-mix makeup gain in decibels (0–24). The room's knob, not the stage's: how much
        /// level this device's output wants on top of the positional mix.
        func setMonitorBoost(decibels: Float) {
            makeupEQ.globalGain = min(max(decibels, 0), 24)
        }

        private static func applying(gain: Float, to samples: [Float]) -> [Float] {
            guard gain != 1 else {
                return samples
            }
            return vDSP.multiply(gain, samples)
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
            queue: SpatialPCMQueue,
            renderQuantumTracker: RenderQuantumTracker? = nil
        ) -> AVAudioSourceNode {
            AVAudioSourceNode(format: format) { isSilence, _, frameCount, outputData in
                if let renderQuantumTracker {
                    let observedFrames = Int(frameCount)
                    let previousFrames = renderQuantumTracker.frames.load(ordering: .relaxed)
                    if observedFrames > previousFrames {
                        renderQuantumTracker.frames.store(observedFrames, ordering: .relaxed)
                    }
                }
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

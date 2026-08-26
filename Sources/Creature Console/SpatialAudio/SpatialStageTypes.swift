#if os(macOS) || os(iOS) || os(tvOS)
    import Accelerate
    import Foundation

    enum SpatialStageInputMode: String, CaseIterable, Identifiable, Sendable {
        case live
        case liveRelay
        case simulation

        var id: String { rawValue }

        var label: String {
            switch self {
            case .live:
                "Live RTP"
            case .liveRelay:
                "Live via Relay"
            case .simulation:
                "Simulation"
            }
        }

        /// Both live modes feed the same pipeline; only the transport differs.
        var isLive: Bool { self != .simulation }
    }

    struct SpatialSimulationSelection: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let soundFile: String
    }

    enum SpatialStageConnectionState: Equatable, Sendable {
        case stopped
        case starting
        case waitingForAudio
        case playing
        case paused
        case failed(String)

        var label: String {
            switch self {
            case .stopped:
                "Stopped"
            case .starting:
                "Starting"
            case .waitingForAudio:
                "Waiting for audio"
            case .playing:
                "Playing"
            case .paused:
                "Paused"
            case .failed(let message):
                message
            }
        }
    }

    enum SpatialLiveTimingMode: Equatable, Sendable {
        case waiting
        case rtcp
        case arrivalFallback
    }

    struct SpatialChannelDiagnostics: Equatable, Identifiable, Sendable {
        let channel: Int
        var packetsReceived: UInt64 = 0
        var invalidPackets: UInt64 = 0
        var concealedFrames: UInt64 = 0
        var fecFrames: UInt64 = 0
        var level: Float = 0
        var lastPacketDate: Date?

        var id: Int { channel }
    }

    struct SpatialStageDiagnostics: Equatable, Sendable {
        var state: SpatialStageConnectionState = .stopped
        var bufferedMilliseconds: Double = 0
        var outputLatencyMilliseconds: Double = 0
        var outputUnderruns: UInt64 = 0
        var rtcpReportsReceived: UInt64 = 0
        var rtcpClockValid = false
        var liveTimingMode: SpatialLiveTimingMode = .waiting
        var rtcpStartLatenessMilliseconds: Double?
        var rtcpPlayoutDelayMilliseconds: Double?
        var rtcpLateFramesDropped: UInt64 = 0
        var channels: [SpatialChannelDiagnostics] = []
        var simulationPosition: TimeInterval = 0
        var simulationDuration: TimeInterval = 0
    }

    enum SpatialAudioLevel {
        static func rootMeanSquare(of samples: [Float]) -> Float {
            guard !samples.isEmpty else {
                return 0
            }

            // Meters run this over every decoded packet on every channel (~800k samples/s
            // while a scene plays), so it has to be the vectorized path. A non-finite
            // sample poisons the vDSP result, which routes those rare defensive cases to
            // the scalar filter below — same ignore-the-garbage semantics the tests pin.
            let vectorized = vDSP.rootMeanSquare(samples)
            if vectorized.isFinite {
                return vectorized
            }

            var energy = 0.0
            var finiteSampleCount = 0

            for sample in samples where sample.isFinite {
                let value = Double(sample)
                energy += value * value
                finiteSampleCount += 1
            }

            guard finiteSampleCount > 0, energy.isFinite else {
                return 0
            }
            let rootMeanSquare = sqrt(energy / Double(finiteSampleCount))
            return rootMeanSquare.isFinite ? Float(rootMeanSquare) : 0
        }

        static func meterLevel(for rootMeanSquare: Float) -> Double {
            guard rootMeanSquare.isFinite else {
                return 0
            }
            return min(max(Double(rootMeanSquare) * 8, 0), 1)
        }
    }

#endif

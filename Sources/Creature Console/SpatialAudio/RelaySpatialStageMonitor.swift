#if os(iOS) || os(tvOS)
    import Common
    import Foundation
    import Observation

    /// Owns the shared spatial-renderer pipeline used by the iPhone, iPad, and Apple TV monitors.
    /// Stage authoring and multicast interface discovery intentionally stay out of this type:
    /// these platforms consume either a saved simulation or live audio through the TCP relay.
    @MainActor
    @Observable
    final class RelaySpatialStageMonitor {
        private(set) var diagnostics = SpatialStageDiagnostics()
        private(set) var isRunning = false

        @ObservationIgnored private var renderer: SpatialAudioRenderer?
        @ObservationIgnored private var liveSource: SpatialLiveAudioSource?
        @ObservationIgnored private var simulationSource: SpatialSimulationAudioSource?
        @ObservationIgnored private var startToken = UUID()

        enum MonitorError: LocalizedError {
            case noAudioLanes
            case noRelayHost
            case invalidPort

            var errorDescription: String? {
                switch self {
                case .noAudioLanes:
                    "This stage has no creatures with audio channels 1–16 to position."
                case .noRelayHost:
                    "Enter the address of a machine running 'creature-cli network rtp-listen'."
                case .invalidPort:
                    "The relay port must be between 1 and 65535."
                }
            }
        }

        func start(
            stage: Stage,
            host: String,
            port: Int,
            headTrackingEnabled: Bool = false,
            monitorBoostDecibels: Float = 0
        ) throws {
            stop()
            let token = UUID()
            startToken = token

            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHost.isEmpty else {
                throw MonitorError.noRelayHost
            }
            let channels = Set(stage.placements.map(\.audioChannel)).filter {
                (1...16).contains($0)
            }
            guard !channels.isEmpty else {
                throw MonitorError.noAudioLanes
            }
            guard (1...65535).contains(port) else {
                throw MonitorError.invalidPort
            }

            try SpatialAudioSession.configureForPlayback()

            let renderer = try SpatialAudioRenderer(
                channels: channels,
                headTrackingEnabled: headTrackingEnabled
            )
            renderer.update(stage: stage)
            renderer.setMonitorBoost(decibels: monitorBoostDecibels)
            let source = try SpatialLiveAudioSource(
                renderer: renderer,
                channels: channels,
                monitoringDelayMilliseconds: stage.audio.monitoringDelayMilliseconds,
                commonPlayoutDelayMilliseconds: stage.audio.commonPlayoutDelayMilliseconds,
                onDiagnostics: { [weak self] diagnostics in
                    Task { @MainActor [weak self] in
                        guard self?.startToken == token else { return }
                        self?.diagnostics = diagnostics
                    }
                }
            )
            try source.start(transport: .relay(host: trimmedHost, port: UInt16(port)))
            self.renderer = renderer
            liveSource = source
            isRunning = true
        }

        func startSimulation(
            stage: Stage,
            soundFile: String,
            headTrackingEnabled: Bool = false,
            looping: Bool = false
        ) async throws {
            stop()
            let token = UUID()
            startToken = token
            isRunning = true
            diagnostics.state = .starting

            do {
                let channels = try audioChannels(for: stage)
                let fileURL = try await SpatialSimulationCache.shared.download(
                    soundFile: soundFile
                )
                try Task.checkCancellation()
                guard startToken == token else { return }
                try SpatialAudioSession.configureForPlayback()

                let renderer = try SpatialAudioRenderer(
                    channels: channels,
                    headTrackingEnabled: headTrackingEnabled
                )
                renderer.update(stage: stage)
                let source = try SpatialSimulationAudioSource(
                    renderer: renderer,
                    fileURL: fileURL,
                    channels: channels,
                    onDiagnostics: { [weak self] diagnostics in
                        Task { @MainActor [weak self] in
                            guard self?.startToken == token else { return }
                            self?.diagnostics = diagnostics
                            if diagnostics.state == .stopped {
                                self?.isRunning = false
                            }
                        }
                    }
                )
                self.renderer = renderer
                simulationSource = source
                source.start(looping: looping)
            } catch {
                guard startToken == token else { return }
                liveSource = nil
                simulationSource = nil
                renderer = nil
                isRunning = false
                diagnostics.state = .failed(error.localizedDescription)
                throw error
            }
        }

        func setPaused(_ paused: Bool) {
            simulationSource?.setPaused(paused)
        }

        func setLooping(_ looping: Bool) {
            simulationSource?.setLooping(looping)
        }

        func seek(to time: TimeInterval) {
            simulationSource?.seek(to: time)
        }

        func setBoost(decibels: Float) {
            renderer?.setMonitorBoost(decibels: decibels)
        }

        func stop() {
            startToken = UUID()
            liveSource?.stop()
            simulationSource?.stop()
            liveSource = nil
            simulationSource = nil
            renderer = nil
            isRunning = false
            diagnostics = SpatialStageDiagnostics()
        }

        private func audioChannels(for stage: Stage) throws -> Set<Int> {
            let channels = Set(stage.placements.map(\.audioChannel)).filter {
                (1...16).contains($0)
            }
            guard !channels.isEmpty else {
                throw MonitorError.noAudioLanes
            }
            return channels
        }
    }
#endif

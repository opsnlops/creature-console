#if os(macOS)
    import Common
    import Foundation
    import Observation

    /// Plays a voice take's 17-channel WAV positioned on a stage — the dialog editor's spatial
    /// audition path.
    ///
    /// A thin lifecycle wrapper over the same pieces the Spatial Stage window uses
    /// (`SpatialAudioRenderer` + `SpatialSimulationAudioSource`), so auditioning a take spatially
    /// and monitoring a show are the identical render path — what you approve is what you'll hear.
    @MainActor
    @Observable
    final class SpatialAuditionPlayer {

        enum AuditionError: LocalizedError {
            case stageHasNoAudioLanes

            var errorDescription: String? {
                switch self {
                case .stageHasNoAudioLanes:
                    "The bound stage has no creatures with audio channels 1–16 to position."
                }
            }
        }

        private(set) var isPlaying = false

        @ObservationIgnored private var renderer: SpatialAudioRenderer?
        @ObservationIgnored private var source: SpatialSimulationAudioSource?
        @ObservationIgnored private var startToken = UUID()

        /// Download (or reuse the cached copy of) the take's 17-channel WAV and play it through
        /// the stage's placements. Candidate exports live in the ad-hoc bucket (`adHoc: true`);
        /// promoted accepted files live in the permanent store.
        func play(soundFile: String, stage: Stage, adHoc: Bool = false) async throws {
            stop()
            let token = UUID()
            startToken = token

            let channels = Set(stage.placements.map(\.audioChannel)).filter {
                (1...16).contains($0)
            }
            guard !channels.isEmpty else { throw AuditionError.stageHasNoAudioLanes }

            let fileURL = try await SpatialSimulationCache.shared.download(
                soundFile: soundFile, adHoc: adHoc)
            guard startToken == token else { return }

            let renderer = try SpatialAudioRenderer(channels: channels)
            renderer.update(stage: stage)
            let source = try SpatialSimulationAudioSource(
                renderer: renderer,
                fileURL: fileURL,
                channels: channels,
                onDiagnostics: { [weak self] diagnostics in
                    Task { @MainActor [weak self] in
                        guard let self, self.startToken == token else { return }
                        if case .stopped = diagnostics.state {
                            self.isPlaying = false
                        }
                    }
                }
            )
            self.renderer = renderer
            self.source = source
            source.start(looping: false)
            isPlaying = true
        }

        func stop() {
            startToken = UUID()
            source?.stop()
            source = nil
            renderer = nil
            isPlaying = false
        }
    }
#endif

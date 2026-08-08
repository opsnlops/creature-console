import Common
import Foundation
import Observation

/// The one local playback facade: every "hear this on THIS machine" path goes through here —
/// flat MP3 renditions and (on macOS) spatial 17-channel playback on a stage.
///
/// A singleton on purpose: there is exactly one set of speakers, and two surfaces playing at
/// once is always a bug. Centralizing also means the flat/spatial mutual exclusion lives in one
/// place instead of being hand-rolled at every call site — which is how it had started to spread
/// (the provenance card, the Voice Take panel, and the animation table each had their own copy).
@MainActor
@Observable
final class LocalAudioPlayer {

    static let shared = LocalAudioPlayer()

    enum Mode {
        case flat
        case spatial
    }

    /// What's playing right now, or nil. Views condition Stop affordances on this.
    private(set) var nowPlaying: Mode?

    var isPlaying: Bool { nowPlaying != nil }

    @ObservationIgnored private let audioManager = AudioManager.shared
    @ObservationIgnored private let server = CreatureServerClient.shared
    #if os(macOS)
        @ObservationIgnored private let spatial = SpatialAuditionPlayer()
    #endif

    private init() {}

    /// Stream a stored sound file's MP3 rendition — the small, flat listen. Works everywhere.
    func playRendition(_ soundFile: String) -> Result<Void, ServerError> {
        stop()
        switch server.getSoundRenditionURL(soundFile, as: .mp3) {
        case .success(let url):
            if case .failure(let error) = audioManager.playURL(url) {
                return .failure(.serverError(error.localizedDescription))
            }
            nowPlaying = .flat
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Play an already-downloaded local file flat (the preview panel's cached auditions).
    /// Routed through here purely so the exclusivity rule can't be bypassed.
    func playLocalFile(_ localURL: URL) -> Result<Void, ServerError> {
        stop()
        if case .failure(let error) = audioManager.playURL(localURL) {
            return .failure(.serverError(error.localizedDescription))
        }
        nowPlaying = .flat
        return .success(())
    }

    #if os(macOS)
        /// Play a 17-channel WAV positioned on a stage — takes (`adHoc: true`) and promoted or
        /// rendered files (`adHoc: false`) alike.
        func playSpatially(_ soundFile: String, stage: Stage, adHoc: Bool = false) async throws {
            stop()
            try await spatial.play(soundFile: soundFile, stage: stage, adHoc: adHoc)
            nowPlaying = .spatial
        }
    #endif

    func stop() {
        audioManager.stopURLPlayback()
        #if os(macOS)
            spatial.stop()
        #endif
        nowPlaying = nil
    }
}

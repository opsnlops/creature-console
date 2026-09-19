import AVFoundation
import Foundation
import OSLog

/// Plays one local audio file with a position the timeline can show and move. Nothing else in
/// the app exposes seek or playback time, so this is the piece editor's own player; it borrows
/// `AudioManager`'s session handling so it never fights the other playback paths.
///
/// `currentTime` is read live from the player, not observed: a view that shows the playhead
/// samples it inside a `TimelineView` while `isPlaying`.
@MainActor
@Observable
final class MusicPiecePlayer {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicPiecePlayer")

    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var loadedURL: URL?
    /// The last position the player was told to be at, so a paused timeline still shows it.
    private(set) var pausedTime: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var finishDelegate: FinishDelegate?
    @ObservationIgnored private var generation = 0

    var currentTime: TimeInterval {
        guard let player else { return pausedTime }
        return isPlaying ? player.currentTime : pausedTime
    }

    /// Loads a file, keeping the playhead where it was if the same file is reloaded.
    func load(url: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        loadedURL = url
        pausedTime = 0
    }

    func unload() {
        stop()
        player = nil
        duration = 0
        loadedURL = nil
        pausedTime = 0
    }

    func play(from time: TimeInterval? = nil) {
        guard let player else { return }
        let start = min(max(time ?? pausedTime, 0), max(duration - 0.05, 0))
        generation += 1
        let token = generation
        let delegate = FinishDelegate { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, token == self.generation else { return }
                self.finish()
            }
        }
        finishDelegate = delegate
        player.delegate = delegate
        AudioManager.shared.beginExternalMusicPlayback()
        player.currentTime = start
        if player.play() {
            isPlaying = true
        } else {
            logger.error("AVAudioPlayer refused to play \(self.loadedURL?.lastPathComponent ?? "")")
            AudioManager.shared.endExternalMusicPlayback()
        }
    }

    func pause() {
        guard let player, isPlaying else { return }
        pausedTime = player.currentTime
        player.pause()
        isPlaying = false
        AudioManager.shared.endExternalMusicPlayback()
    }

    func stop() {
        guard let player else { return }
        generation += 1
        pausedTime = 0
        if isPlaying {
            player.stop()
            isPlaying = false
            AudioManager.shared.endExternalMusicPlayback()
        }
        player.currentTime = 0
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(time, 0), max(duration - 0.05, 0))
        pausedTime = clamped
        if let player, isPlaying {
            player.currentTime = clamped
        }
    }

    private func finish() {
        pausedTime = 0
        isPlaying = false
        player?.currentTime = 0
        AudioManager.shared.endExternalMusicPlayback()
    }
}

/// Bridges the delegate callback (any thread) to the player on the main actor. AVAudioPlayer
/// holds its delegate weakly, so the player keeps this alive.
private final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        onFinish()
    }
}

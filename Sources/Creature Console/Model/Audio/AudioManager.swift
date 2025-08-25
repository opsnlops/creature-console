import AVFoundation
import AVKit
import Common
import Foundation
import OSLog

@MainActor
class AudioManager: ObservableObject {

    // Only one of these can / should exist, so let's use the Singleton pattern
    static let shared = AudioManager()

    let server = CreatureServerClient.shared

    private var player: AVPlayer?
    private var audioPlayer: AVAudioPlayer?
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AudioManager")

    @Published var volume: Float {

        // If the user updates the volume, update the preferences
        didSet {
            UserDefaults.standard.set(volume, forKey: "audioVolume")
        }
    }

    // This is private to make it impossible to make more tha one
    private init() {

        self.volume = UserDefaults.standard.float(forKey: "audioVolume")

        #if os(iOS)
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to set audio session category.")
            }
        #endif
    }


    func playURL(_ url: URL) -> Result<String, AudioError> {

        logger.debug("Attempting to play \(url)")

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        self.player = AVPlayer(playerItem: playerItem)
        player?.play()

        return .success("Played \(url)")

    }


    func playBundledSound(name: String, extension: String) -> Result<String, AudioError> {
        guard let url = Bundle.main.url(forResource: name, withExtension: `extension`) else {
            logger.error("Couldn't find the bundled sound file.")
            return .failure(.fileNotFound("Couldn't find the bundled sound file!"))
        }

        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: url)
            self.audioPlayer?.play()

            return .success("File queued up to play!")
        } catch {
            logger.error("Failed to initialize AVAudioPlayer: \(error)")
            return .failure(
                .systemError("Failed to initialize AVAudioPlayer: \(error.localizedDescription)"))
        }
    }

    func pause() {
        logger.info("pausing audio")
        self.audioPlayer?.pause()
    }
}

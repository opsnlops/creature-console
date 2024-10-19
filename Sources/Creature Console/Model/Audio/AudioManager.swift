import AVFoundation
import AVKit
import Common
import Foundation
import OSLog

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

    func playSoundFile(fileName: String) async -> Result<String, AudioError> {
        logger.debug("Attempting to play \(fileName) locally")

        var soundUrl: URL?

        let urlResult = server.getSoundURL(fileName)
        switch(urlResult) {
        case .failure(let error):
            logger.warning("Failed to get sound URL: \(error.localizedDescription)")
            return .failure(.systemError(error.localizedDescription))
        case .success(let url):
            logger.debug("URL to play is: \(url.absoluteString)")
            soundUrl = url
        }

        // Make sure we have valid URL
        guard let soundUrl else {
            return .failure(.fileNotFound("🔎 No URL to play"))
        }

        // If this is in the local scope, it will go out of scope before
        // the file even starts playing
        logger.debug("calling AVPlayer.play")
        self.player = AVPlayer(url: soundUrl)
        player?.volume = volume
        player?.play()

        return .success("Played \(fileName)")
    }

    func playFileName(url: URL) async -> Result<String, AudioError> {
        logger.info("Attempting to play \(url)")

        // Check if the file exists at the given URL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            logger.error("File not found at URL: \(url)")
            return .failure(.fileNotFound("🔎 File not found at URL: \(url)"))
        }

        // Begin accessing a security-scoped resource.
        let didStartAccessing = url.startAccessingSecurityScopedResource()

        if didStartAccessing {
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                self.audioPlayer = try AVAudioPlayer(contentsOf: url)
                // Instead of immediately playing, wait for audioPlayer to be prepared to play
                guard self.audioPlayer?.prepareToPlay() ?? false else {
                    logger.error("AVAudioPlayer failed to prepare.")
                    return .failure(.systemError("🔇 AVAudioPlayer failed to prepare."))
                }
                self.audioPlayer?.play()

            } catch {
                logger.error("Failed to initialize AVAudioPlayer: \(error.localizedDescription)")
                return .failure(
                    .systemError(
                        "🔇 Failed to initialize AVAudioPlayer: \(error.localizedDescription)"))
            }
        } else {
            logger.error("Couldn't access the security scoped resource.")
            return .failure(.fileNotFound("🚫 Couldn't access the security scoped resource."))
        }

        self.logger.debug("Played \(url) successfuly!")
        return .success("🎼 Played \(url)!")
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

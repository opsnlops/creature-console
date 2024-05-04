
import AVFoundation
import Foundation
import OSLog


class AudioManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AudioManager")
    
    @Published var volume: Float {
        
        // If the user updates the volume, update the preferences
        didSet {
            UserDefaults.standard.set(volume, forKey: "audioVolume")
        }
    }
    
    init() {
        
        self.volume = UserDefaults.standard.float(forKey: "audioVolume")
        
#if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category.")
        }
#endif
    }

    
    
    func play(url: URL) async throws {
        logger.info("Attempting to play \(url)")

        // Check if the file exists at the given URL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            logger.error("File not found at URL: \(url)")
            throw AudioError.fileNotFound("🔎 File not found at URL: \(url)")
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
                    throw AudioError.systemError("🔇 AVAudioPlayer failed to prepare.")
                }
                self.audioPlayer?.play()
                
                // Assuming you want to wait for the audio to finish playing:
                //await waitForAudioToEnd()
            } catch {
                logger.error("Failed to initialize AVAudioPlayer: \(error)")
                throw AudioError.systemError("🔇 Failed to initialize AVAudioPlayer: \(error)")
            }
        } else {
            logger.error("Couldn't access the security scoped resource.")
            throw AudioError.fileNotFound("🚫 Couldn't access the security scoped resource.")
        }
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
            return .failure(.systemError("Failed to initialize AVAudioPlayer: \(error.localizedDescription)"))
        }
    }
    
    func pause() {
        logger.info("pausing audio")
        self.audioPlayer?.pause()
    }
}



extension AudioManager {
    static func mock() -> AudioManager {
        let mock = Mock()
        mock.volume = 0.5
        return mock
    }
    
    private class Mock: AudioManager {
        override func play(url: URL) async throws {
            // Do nothing in mock
            logger.info("MockAudioManager play called with \(url)")
        }
        
        override func playBundledSound(name: String, extension: String) -> Result<String, AudioError> {
            // Do nothing in mock
            logger.info("MockAudioManager playBundledSound called with \(name)")
            return .success("MockAudioManager playBundledSound called with \(name)")
        }

        override func pause() {
            // Do nothing in mock
            logger.info("MockAudioManager pause called")
        }
    }
}

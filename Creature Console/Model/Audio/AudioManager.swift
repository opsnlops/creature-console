//
//  AudioManager.swift
//  Creature Console
//
//  Created by April White on 5/11/23.
//

import AVFoundation
import Foundation
import Logging


class AudioManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    let logger = Logger(label: "Audio Manager")
    
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

    func play(url: URL) {
        logger.info("attempting to play \(url)")
        
        // Begin accessing a security-scoped resource.
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        
        if didStartAccessing {
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                self.audioPlayer = try AVAudioPlayer(contentsOf: url)
                self.audioPlayer?.play()
            } catch {
                logger.error("Failed to initialize AVAudioPlayer: \(error)")
            }
        } else {
            logger.error("Couldn't access the security scoped resource.")
        }
    }

    func playBundledSound(name: String, extension: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: `extension`) else {
            logger.error("Couldn't find the bundled sound file.")
            return
        }
        
        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: url)
            self.audioPlayer?.play()
        } catch {
            logger.error("Failed to initialize AVAudioPlayer: \(error)")
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
        override func play(url: URL) {
            // Do nothing in mock
            logger.info("MockAudioManager play called with \(url)")
        }

        override func pause() {
            // Do nothing in mock
            logger.info("MockAudioManager pause called")
        }
    }
}
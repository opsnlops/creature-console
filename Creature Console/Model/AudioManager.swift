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

    func pause() {
        logger.info("pausing audio")
        self.audioPlayer?.pause()
    }
}

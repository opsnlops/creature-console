//
//  AudioFileManager.swift
//  Creature Console
//
//  Created by April White on 5/10/23.
//

import AVFoundation
import Foundation
import Logging


class AudioManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    let logger = Logger(label: "Audio Manager")
    
    
    init() {
        
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

class AudioFileManager : ObservableObject {
    
    let logger = Logger(label: "Audio File Manager")
    
    
    func getiCloudContainerURL() -> URL? {
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }

    
    func saveFileToiCloud(audioData: Data, fileName: String) {
        guard let containerURL = getiCloudContainerURL() else { return }
        let fileURL = containerURL.appendingPathComponent(fileName)

        do {
            try audioData.write(to: fileURL, options: .atomicWrite)
        } catch {
            print("Error saving file to iCloud: \(error)")
        }
    }

    func loadFileFromiCloud(fileName: String) -> Data? {
        
        
        guard let containerURL = getiCloudContainerURL() else { return nil }
        let fileURL = containerURL.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: fileURL)
            return data
        } catch {
            print("Error loading file from iCloud: \(error)")
            return nil
        }
    }

    func listAllFilesIniCloud() -> [URL]? {
        
        logger.info("listing all files in iCloud")
        
        guard let containerURL = getiCloudContainerURL() else { return nil }
        logger.info("containerURL: \(containerURL.pathComponents)")
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            return fileURLs
        } catch {
            print("Error listing files in iCloud container: \(error)")
            return nil
        }
    }

    
    
}

//
//  AudioFileManager.swift
//  Creature Console
//
//  Created by April White on 5/10/23.
//

import AVFoundation
import Foundation
import Logging


class StorageManager : ObservableObject {
    
    let logger = Logger(label: "Storage Manager")
    
    
    func getiCloudContainerURL() -> URL? {
        
        // If 'forUbiquityContainerIdentifier' is nil, it will take the first one we've got. Since
        // there's only one, it will take that.
        let containerUrl = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
        
        logger.info("iCloud Container URL: \(String(describing: containerUrl))")
        
        return containerUrl
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

//
//  SoundDataImporter.swift
//  Creature Console
//
//  Created by April White on 8/22/23.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Logging

struct SoundDataImport: View {
    @State private var jsonString: String = ""
    @State private var isFileImporterPresented: Bool = false

    @Binding var animation: Animation?
    
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    
    var soundDataProcessor = SoundDataProcessor()
    
    let logger = Logger(label: "Sound Data Import")
    
   
    var body: some View {
        VStack {
            Button("Import Mouth Data to Track 5") {
                isFileImporterPresented = true
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let url = try result.get().first!
                    let jsonData = try Data(contentsOf: url)
                    jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                    
                    // Display the jsonString here if needed
                    let decoder = JSONDecoder()
                    if let soundData = try? decoder.decode(SoundData.self, from: jsonData) {
                        print("Sound file path: \(soundData.metadata.soundFile)")
                        print("First mouth cue value: \(soundData.mouthCues.first?.value ?? "")")
                        if let a = animation {
                            soundDataProcessor.replaceTrackDataWithSoundData(soundData: soundData, track: 5, animation: a)
                        }
                        else {
                            logger.info("didn't do anything since animation is nil")
                        }
                    }
                    
                    
                } catch {
                    // Handle the error
                    logger.warning("Failed to sound data file: \(error)")
                    alertMessage = "Failed to sound data file: \(error)"
                    showErrorAlert = true
                }
            }
            
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Grrrr"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Fuck"))
            )
        }
        
    }
}
    

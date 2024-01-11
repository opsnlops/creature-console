//
//  AudioFilePicker.swift
//  Creature Console
//
//  Created by April White on 5/10/23.
//
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import OSLog


struct AudioFilePicker: View {
 
    @EnvironmentObject var audioManager: AudioManager

    @State private var importURL: URL?
    @State private var showImportAudioSheet = false

    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    
    @AppStorage("audioFilePath") private var audioFilePath: String = ""
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AudioFilePicker")
    
    private var audioData = Data()
    
    var body: some View {
        VStack {

            Button("Play Audio File") {
                showImportAudioSheet = true
            }
            .fileImporter(
                isPresented: $showImportAudioSheet,
                allowedContentTypes: [.audio],
                onCompletion: { result in
                    do {
                        let fileURL = try result.get()
                        
                        // Store this path to where the sounds are
                        audioFilePath = fileURL.deletingLastPathComponent().absoluteString
                        
                        let playResult = audioManager.play(url: fileURL)
                        switch(playResult) {
                        case .success(let data):
                            logger.info("Played audio file: \(data)")
                        case .failure(let error):
                            logger.error("Error playing audio: \(error)")
                            alertMessage = "Error playing audio: \(error)"
                            showErrorAlert = true
                        }
                        
                        
                    } catch {
                        logger.warning("Failed to read audio file: \(error)")
                        alertMessage = "Failed to read audio file: \(error)"
                        showErrorAlert = true
                    }
                }
            )
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Grrrr"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Fuck"))
                )
            }
        }
    }
}



struct AudioFilePicker_Previews: PreviewProvider {
    static var previews: some View {
        AudioFilePicker()
            .environmentObject(AudioManager.mock())
    }
}


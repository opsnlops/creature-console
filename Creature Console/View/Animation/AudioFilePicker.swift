//
//  AudioFilePicker.swift
//  Creature Console
//
//  Created by April White on 5/10/23.
//
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import Logging


struct AudioFilePicker: View {
 
    @EnvironmentObject var audioManager: AudioManager

    @State private var importURL: URL?
    @State private var showImportAudioSheet = false

    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    
    @AppStorage("audioFilePath") private var audioFilePath: String = ""
    
    let logger = Logger(label: "Audio File Picker")
    
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
                        
                        audioManager.play(url: fileURL)
                        
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


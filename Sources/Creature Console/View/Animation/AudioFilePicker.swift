
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import OSLog


struct AudioFilePicker: View {
 
    let audioManager = AudioManager.shared

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
                    // Start a new asynchronous task to handle the async function
//                    Task {
//                        do {
//                            let fileURL = try result.get()
//                            
//                            // Store this path to where the sounds are
//                            audioFilePath = fileURL.deletingLastPathComponent().absoluteString
//                            
//                            // Call the async function using `await`
//                            let playResult = try await audioManager.play(url: fileURL)
//                            logger.info("Played audio file: \(playResult)")
//                        } catch {
//                            logger.error("Error playing audio: \(error)")
//                            alertMessage = "Error playing audio: \(error)"
//                            showErrorAlert = true
//                        }
//                    }
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
    }
}


import Common
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct SoundDataImport: View {

    @State private var jsonString: String = ""
    @State private var isFileImporterPresented: Bool = false

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    var soundDataProcessor = SoundDataProcessor()
    @Binding var track: Track

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundDataImport")

    var body: some View {
        VStack {
            Button("Import Mouth Data to Axis 4") {
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

                    let decoder = JSONDecoder()
                    if let soundData = try? decoder.decode(SoundData.self, from: jsonData) {
                        print("Sound file path: \(soundData.metadata.soundFile)")
                        print("First mouth cue value: \(soundData.mouthCues.first?.value ?? "")")
                        if let a = AppState.shared.currentAnimation {
                            let result = soundDataProcessor.replaceAxisDataWithSoundData(
                                soundData: soundData, axis: 4, track: track,
                                millisecondsPerFrame: a.metadata.millisecondsPerFrame)
                            switch result {
                            case .success(let updatedTrack):
                                track = updatedTrack
                            case .failure(let error):
                                logger.warning("Failed to update track: \(error)")
                                alertMessage = "Failed to update track: \(error)"
                                showErrorAlert = true
                            }
                        } else {
                            logger.info("didn't do anything since animation is nil")
                        }
                    }

                } catch {
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
                dismissButton: .default(Text("Dismiss"))
            )
        }
    }
}

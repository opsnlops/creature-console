import AVFoundation
import Common
import Foundation
import OSLog
import SwiftUI

struct SoundFileTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundFileTable")

    @State private var soundListCacheState = SoundListCacheState(sounds: [:], empty: true)

    // Our Server
    let server = CreatureServerClient.shared
    let audioManager = AudioManager.shared

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    @State private var selection: Common.Sound.ID? = nil

    @State private var playSoundTask: Task<Void, Never>? = nil

    @State var player: AVPlayer? = nil

    var body: some View {
        NavigationStack {
            VStack {
                if !soundListCacheState.sounds.isEmpty {
                    Table(of: Common.Sound.self, selection: $selection) {
                        TableColumn("File Name", value: \.fileName)
                            .width(min: 300, ideal: 500)

                        TableColumn("Size (bytes)") { s in
                            Text(s.size, format: .number)
                        }
                        .width(min: 120)

                        TableColumn("Text?") { s in
                            Text(s.transcript.isEmpty ? "" : "✅")
                        }
                        .width(100)

                    } rows: {
                        ForEach(
                            soundListCacheState.sounds.values.sorted(by: {
                                $0.fileName < $1.fileName
                            })
                        ) { sound in
                            TableRow(sound)
                                .contextMenu {
                                    Button {
                                        playSelectedOnServer()
                                    } label: {
                                        Label(
                                            "Play Sound File On Server",
                                            systemImage: "music.note.tv")
                                    }

                                    Button {
                                        playSelectedLocally()
                                    } label: {
                                        Label(
                                            "Play Sound File Locally",
                                            systemImage: "music.quarternote.3")
                                    }

                                    Button {
                                        print("show transcript")
                                    } label: {
                                        Label("View Transcript", systemImage: "text.bubble.fill")
                                    }
                                    .disabled(sound.transcript.isEmpty)


                                }  //context Menu
                        }  // ForEach
                    }  // rows
                }  // if !availableSoundFiles.isEmpty

            }  // VStack
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("No Sounds for Us"))
                )
            }
            .navigationTitle("Sound Files")
            #if os(macOS)
                .navigationSubtitle("Number of Sounds: \(self.soundListCacheState.sounds.count)")
            #endif
            .task {
                for await state in await SoundListCache.shared.stateUpdates {
                    await MainActor.run {
                        soundListCacheState = state
                    }
                }
            }
        }  // Navigation Stack
    }  // View


    func playSelectedOnServer() {

        logger.debug("Attempting to play the selected sound file on the server")

        playSoundTask?.cancel()

        playSoundTask = Task {

            // Go see what, if anything, is selected
            if let sound = selection {
                let result = await server.playSound(sound)
                switch result {
                case .success(let message):
                    print(message)
                case .failure(let error):
                    DispatchQueue.main.async {
                        alertMessage = "Error: \(String(describing: error.localizedDescription))"
                        logger.warning(
                            "Unable to play a sound file: \(String(describing: error.localizedDescription))"
                        )
                        showErrorAlert = true
                    }

                }
            }

        }

    }

    func playSelectedLocally() {

        logger.debug("Attempting to play the selected sound file locally")

        playSoundTask?.cancel()

        playSoundTask = Task {

            if let sound = selection {

                let urlRequest = server.getSoundURL(sound)
                switch urlRequest {
                case .success(let url):

                    logger.info("Playing \(url)")
                    _ = audioManager.playURL(url)

                case .failure(let error):

                    DispatchQueue.main.async {
                        alertMessage = "Error: \(String(describing: error.localizedDescription))"
                        logger.warning(
                            "Unable to play a sound file: \(String(describing: error.localizedDescription))"
                        )
                    }
                    showErrorAlert = true
                }

            }

        }

    }


}  // struct

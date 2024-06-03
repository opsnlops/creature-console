import Common
import Foundation
import OSLog
import SwiftUI

struct SoundFileTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundFileTable")


    // Our Server
    let server = CreatureServerClient.shared

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    @State var availableSoundFiles: [Common.Sound] = []
    @State private var selection: Common.Sound.ID? = nil

    @State private var loadDataTask: Task<Void, Never>? = nil
    @State private var playSoundTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack {
                if !availableSoundFiles.isEmpty {
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
                        ForEach(availableSoundFiles) { sound in
                            TableRow(sound)
                                .contextMenu {
                                    Button {
                                        playSelected()
                                    } label: {
                                        Label("Play Sound File", systemImage: "music.quarternote.3")
                                    }
                                    //.disabled(sound.transcript.isEmpty)

                                    Button {
                                        print("show transscript")
                                    } label: {
                                        Label("View Transcript", systemImage: "text.bubble.fill")
                                    }
                                    .disabled(sound.transcript.isEmpty)


                                }  //context Menu
                        }  // ForEach
                    }  // rows
                }  // if !availableSoundFiles.isEmpty

            }  // VStack
            .onAppear {
                logger.debug("onAppear()")
                loadData()
            }
            .onDisappear {
                loadDataTask?.cancel()
            }
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Unable to the list of sound files"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("No Music for Us"))
                )
            }
            .navigationTitle("Sound Files")
            #if os(macOS)
                .navigationSubtitle("Number of Sounds: \(self.availableSoundFiles.count)")
            #endif
        }  // Navigation Stack
    }  // View


    func loadData() {
        loadDataTask?.cancel()

        loadDataTask = Task {

            // Go fetch all of the sound files
            let result = await server.listSounds()
            logger.debug("Loaded all sound")

            switch result {
            case .success(let data):
                logger.debug("success!")
                self.availableSoundFiles = data
            case .failure(let error):
                alertMessage = "Error: \(String(describing: error.localizedDescription))"
                logger.warning(
                    "Unable to load the list of sound files: \(String(describing: error.localizedDescription))"
                )
                showErrorAlert = true
            }
        }
    }

    func playSelected() {

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

}  // struct

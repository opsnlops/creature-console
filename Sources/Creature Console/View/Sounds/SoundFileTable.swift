import AVFoundation
import Common
import Foundation
import OSLog
import SwiftUI

#if os(iOS)
import UIKit
#endif

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
    @State private var preparingFile: String? = nil

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
                                        playOnServer(fileName: sound.fileName)
                                    } label: {
                                        Label(
                                            "Play Sound File On Server",
                                            systemImage: "music.note.tv")
                                    }

                                    Button {
                                        playLocally(fileName: sound.fileName)
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
                // First, get the current state immediately
                let currentState = await SoundListCache.shared.getCurrentState()
                await MainActor.run {
                    soundListCacheState = currentState
                }

                // Then listen for updates
                for await state in await SoundListCache.shared.stateUpdates {
                    await MainActor.run {
                        soundListCacheState = state
                    }
                }
            }
            #if os(iOS)
            .toolbar(id: "global-bottom-status") {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    ToolbarItem(id: "status", placement: .bottomBar) {
                        BottomStatusToolbarContent()
                    }
                }
            }
            #endif
            .overlay {
                if let name = preparingFile {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing \(name)…")
                                .font(.callout)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.default, value: preparingFile != nil)
        }  // Navigation Stack
    }  // View


    func playOnServer(fileName: String) {

        logger.debug("Attempting to play the selected sound file on the server")

        playSoundTask?.cancel()

        playSoundTask = Task {

            let result = await server.playSound(fileName)
            switch result {
            case .success(let message):
                print(message)
            case .failure(let error):
                await MainActor.run {
                    alertMessage = "Error: \(String(describing: error.localizedDescription))"
                    logger.warning(
                        "Unable to play a sound file: \(String(describing: error.localizedDescription))"
                    )
                    showErrorAlert = true
                }
            }
        }
    }


    func playLocally(fileName: String) {

        logger.debug("Attempting to play the selected sound file locally")

        playSoundTask?.cancel()

        playSoundTask = Task {
            await MainActor.run { preparingFile = fileName }

            let urlRequest = server.getSoundURL(fileName)
            switch urlRequest {
            case .success(let url):

                if fileName.lowercased().hasSuffix(".wav") {
                    // For WAVs, prepare a mono preview and play via AVAudioEngine
                    logger.info("Preparing mono preview for WAV: \(fileName)")
                    let prepResult = await audioManager.prepareMonoPreview(for: url, cacheKey: fileName)
                    switch prepResult {
                    case .success(let monoURL):
                        let armResult = audioManager.armPreviewPlayback(fileURL: monoURL)
                        switch armResult {
                        case .success:
                            _ = audioManager.startArmedPreview(in: 0.1)
                            await MainActor.run { preparingFile = nil }
                        case .failure(let err):
                            await MainActor.run {
                                alertMessage = "Error: \(err)"
                                logger.warning("Unable to arm preview: \(String(describing: err))")
                                showErrorAlert = true
                                preparingFile = nil
                            }
                        }
                    case .failure(let err):
                        await MainActor.run {
                            alertMessage = "Error: \(err)"
                            logger.warning("Unable to prepare mono preview: \(String(describing: err))")
                            showErrorAlert = true
                            preparingFile = nil
                        }
                    }
                } else {
                    // For non-WAVs, fall back to AVPlayer
                    logger.info("Playing via AVPlayer: \(url)")
                    _ = audioManager.playURL(url)
                    await MainActor.run { preparingFile = nil }
                }

            case .failure(let error):

                await MainActor.run {
                    alertMessage = "Error: \(String(describing: error.localizedDescription))"
                    logger.warning(
                        "Unable to play a sound file: \(String(describing: error.localizedDescription))"
                    )
                    showErrorAlert = true
                    preparingFile = nil
                }
            }
        }
    }


}  // struct

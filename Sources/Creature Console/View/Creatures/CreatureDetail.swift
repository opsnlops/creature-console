import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

struct CreatureDetail: View {

    @AppStorage("mfm2023PlaylistHack") private var mfm2023PlaylistHack: PlaylistIdentifier = ""
    @AppStorage("activeUniverse") private var activeUniverse: UniverseIdentifier = 1


    let server = CreatureServerClient.shared
    let eventLoop = EventLoop.shared
    @ObservedObject var appState = AppState.shared
    let creatureManager = CreatureManager.shared


    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var streamingTask: Task<Void, Never>? = nil

    var creature: Creature

    @State private var isDoingServerStuff: Bool = false
    @State private var serverMessage: String = ""

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                #if os(macOS)
                SensorData(creature: creature)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                #else
                SensorData(creature: creature)
                #endif
            }
            .padding()
        }
        .toolbar(id: "\(creature.name) creatureDetail") {
            #if os(iOS)
                ToolbarItem(id: "inputs", placement: .navigationBarTrailing) {
                    NavigationLink(destination: InputTableView(creature: creature)) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItem(id: "control", placement: .navigationBarTrailing) {
                    Button(action: {
                        toggleStreaming()
                    }) {
                        Image(
                            systemName: (appState.currentActivity == .streaming)
                                ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .foregroundColor(
                            (appState.currentActivity == .streaming) ? .green : .primary)
                    }
                }
            #else
                ToolbarItem(id: "inputs", placement: .secondaryAction) {
                    NavigationLink(destination: InputTableView(creature: creature)) {
                        Image(systemName: "slider.horizontal.3")
                            .glassEffect(.regular)
                    }
                    .help("View Input Configuration")
                }
                ToolbarItem(id: "control", placement: .primaryAction) {
                    Button(action: {
                        toggleStreaming()
                    }) {
                        Label("Toggle Streaming", systemImage: (appState.currentActivity == .streaming)
                            ? "gamecontroller.fill" : "gamecontroller")
                            .labelStyle(.iconOnly)
                            .symbolRenderingMode(.monochrome)
                    }
                    .glassEffect(.regular.tint((appState.currentActivity == .streaming) ? .green : .none).interactive())
                    .help("Toggle Streaming")
                }
            #endif
        }.toolbarRole(.editor)
        .overlay {
            if isDoingServerStuff {
                Text(serverMessage)
                    .font(.title)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
        }
        .onDisappear {
            streamingTask?.cancel()
        }
        .navigationTitle(creature.name)
        #if os(macOS)
            .navigationSubtitle(generateStatusString())
        #endif

    }


    func generateStatusString() -> String {
        let status =
            "ID: \(creature.id), Offset: \(creature.channelOffset), Active Universe: \(activeUniverse)"
        return status
    }

    func stopPlaylistPlayback() {

        logger.info("stopping playlist playback on server")
        serverMessage = "Sending stop playing signal..."
        isDoingServerStuff = true

        Task {
            do {
                let result = try await server.stopPlayingPlaylist(universe: activeUniverse)

                switch result {
                case .failure(let value):
                    DispatchQueue.main.async {
                        errorMessage = "Unable to stop playlist playback: \(value)"
                        showErrorAlert = true
                    }
                case .success(let value):
                    logger.info("stopped! \(value)")
                    serverMessage = value
                }


            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Unable to stop playlist playback: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }

            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {}
            isDoingServerStuff = false
        }
    }


    func startMFM2023Playlist() {

        logger.info("Doing the gross thing")
        serverMessage = "🤢 Doing the gross thing"
        isDoingServerStuff = true

        if let playlistId = DataHelper.stringToOidData(oid: mfm2023PlaylistHack) {

            logger.debug(
                "string: \(mfm2023PlaylistHack), data: \(DataHelper.dataToHexString(data: playlistId))"
            )

            Task {
                do {
                    let result = try await server.startPlayingPlaylist(
                        universe: activeUniverse, playlistId: mfm2023PlaylistHack)

                    switch result {
                    case .failure(let value):
                        DispatchQueue.main.async {
                            errorMessage = "Unable to start playlist playback: \(value)"
                            showErrorAlert = true
                        }
                    case .success(let value):
                        logger.info("Gross hack accomplished! 🤮! \(value)")
                        serverMessage = value
                    }


                } catch {
                    DispatchQueue.main.async {
                        errorMessage =
                            "Unable to start the gross hack: \(error.localizedDescription)"
                        showErrorAlert = true
                    }
                }

                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {}
                isDoingServerStuff = false
            }
        } else {
            DispatchQueue.main.async {
                errorMessage = "Can't convert \(mfm2023PlaylistHack) to an OID"
                showErrorAlert = true
            }

        }
    }


    func toggleStreaming() {

        logger.info("Toggling streaming")

        if appState.currentActivity == .idle {

            logger.debug("starting streaming")
            streamingTask?.cancel()
            streamingTask = Task {
                DispatchQueue.main.async {
                    appState.currentActivity = .streaming
                }

                let result = creatureManager.startStreamingToCreature(creatureId: creature.id)
                switch result {
                case .success(let message):
                    logger.info("Streaming result: \(message)")
                case .failure(let error):
                    logger.warning("Unable to stream: \(error)")
                    DispatchQueue.main.async {
                        errorMessage = "Unable to start streaming: \(error)"
                        showErrorAlert = true
                    }
                }
            }
        } else {
            // If we're streaming, stop
            if appState.currentActivity == .streaming {

                logger.debug("stopping streaming")
                let result = creatureManager.stopStreaming()
                switch result {
                case .success:
                    logger.debug("we were able to stop streaming!")
                case .failure(let message):
                    logger.warning("Unable to stop streaming: \(message)")
                }

                streamingTask?.cancel()
                DispatchQueue.main.async {
                    appState.currentActivity = .idle
                }

            } else {

                DispatchQueue.main.async {
                    errorMessage =
                        "Unable to start streaming while in the \(appState.currentActivity.description) state"
                    showErrorAlert = true
                }

            }
        }
    }
}


#Preview {
    CreatureDetail(creature: .mock())
}


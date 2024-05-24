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
        VStack {
            AnimationTable(creature: creature)
        }
        .toolbar(id: "\(creature.name) creatureDetail") {
            ToolbarItem(id: "control", placement: .primaryAction) {
                Button(action: {
                    toggleStreaming()
                }) {
                    Image(
                        systemName: (appState.currentActivity == .streaming)
                            ? "gamecontroller.fill" : "gamecontroller"
                    )
                    .foregroundColor((appState.currentActivity == .streaming) ? .green : .primary)
                }
            }
            ToolbarItem(id: "recordAnimation", placement: .secondaryAction) {
                NavigationLink(
                    destination: RecordTrack(
                        creature: creature
                    ),
                    label: {
                        Image(systemName: "record.circle")
                    })
            }
            ToolbarItem(id: "creatureConfiguration", placement: .secondaryAction) {
                NavigationLink(
                    destination: CreatureConfiguration(creature: creature),
                    label: {
                        Image(systemName: "sparkle.magnifyingglass")
                    })
            }
//            ToolbarItem(id: "startMFM2023PlaylistPlayback", placement: .secondaryAction) {
//                Button(action: {
//                    startMFM2023Playlist()
//                }) {
//                    Image(systemName: "pawprint")
//                }
//            }
//            ToolbarItem(id: "stopPlaylistPlayback", placement: .secondaryAction) {
//                Button(action: {
//                    stopPlaylistPlayback()
//                }) {
//                    Image(systemName: "stop.circle.fill")
//                        .foregroundColor(.red)
//                }
//            }
        }.toolbarRole(.editor)
        .overlay {
            if isDoingServerStuff {
                Text(serverMessage)
                    .font(.title)
                    .padding()
                    .background(Color.green.opacity(0.4))
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
        let status = "Offset: \(creature.channelOffset), Active Universe: \(activeUniverse)"
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


struct CreatureDetail_Previews: PreviewProvider {
    static var previews: some View {
        CreatureDetail(creature: .mock())
    }
}

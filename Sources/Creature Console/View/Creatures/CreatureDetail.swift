import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

struct CreatureDetail: View {

    @AppStorage("mfm2023PlaylistHack") private var mfm2023PlaylistHack: PlaylistIdentifier = ""
    @AppStorage("activeUniverse") private var activeUniverse: UniverseIdentifier = 1


    let server = CreatureServerClient.shared

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var currentActivity: Activity = .idle

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
                            systemName: (currentActivity == .streaming)
                                ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .foregroundColor(
                            (currentActivity == .streaming) ? .green : .primary)
                    }
                }
            #else
                ToolbarItem(id: "inputs", placement: .secondaryAction) {
                    NavigationLink(destination: InputTableView(creature: creature)) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("View Input Configuration")
                }
                ToolbarItem(id: "control", placement: .primaryAction) {
                    Button(action: {
                        toggleStreaming()
                    }) {
                        Label(
                            "Toggle Streaming",
                            systemImage: (currentActivity == .streaming)
                                ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .labelStyle(.iconOnly)
                        .foregroundColor(
                            (currentActivity == .streaming) ? .green : .primary)
                    }
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
        .onAppear {
            Task {
                let appStateActivity = await AppState.shared.getCurrentActivity
                await MainActor.run {
                    currentActivity = appStateActivity
                }
            }
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
            let result = await server.stopPlayingPlaylist(universe: activeUniverse)

            switch result {
            case .failure(let value):
                await MainActor.run {
                    errorMessage = "Unable to stop playlist playback: \(value)"
                    showErrorAlert = true
                }
            case .success(let value):
                logger.info("stopped! \(value)")
                serverMessage = value
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
                let result = await server.startPlayingPlaylist(
                    universe: activeUniverse, playlistId: mfm2023PlaylistHack)

                switch result {
                case .failure(let value):
                    await MainActor.run {
                        errorMessage = "Unable to start playlist playback: \(value)"
                        showErrorAlert = true
                    }
                case .success(let value):
                    logger.info("Gross hack accomplished! 🤮! \(value)")
                    serverMessage = value
                }

                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {}
                isDoingServerStuff = false
            }
        } else {
            Task {
                await MainActor.run {
                    errorMessage = "Can't convert \(mfm2023PlaylistHack) to an OID"
                    showErrorAlert = true
                }
            }
        }
    }


    func toggleStreaming() {
        Task {
            // Check AppState directly to avoid race conditions
            let appStateActivity = await AppState.shared.getCurrentActivity
            logger.info("toggleStreaming called - AppState: \(appStateActivity.description)")

            // Simple toggle: if streaming, stop. If not streaming, start.
            if appStateActivity == .streaming {
                // Stop streaming
                let result = await CreatureManager.shared.stopStreaming()
                switch result {
                case .success:
                    logger.debug("Successfully stopped streaming")
                    await AppState.shared.setCurrentActivity(.idle)
                    await MainActor.run {
                        currentActivity = .idle
                    }
                case .failure(let error):
                    logger.warning("Failed to stop streaming: \(error)")
                // Don't change AppState if stopping failed
                }

            } else {
                // Start streaming (from any other state)
                await AppState.shared.setCurrentActivity(.streaming)
                let result = await CreatureManager.shared.startStreamingToCreature(
                    creatureId: creature.id)
                switch result {
                case .success(let message):
                    logger.info("Successfully started streaming: \(message)")
                    await MainActor.run {
                        currentActivity = .streaming
                    }
                case .failure(let error):
                    logger.warning("Failed to start streaming: \(error)")
                    // Revert state on failure
                    await AppState.shared.setCurrentActivity(.idle)
                    await MainActor.run {
                        currentActivity = .idle
                        errorMessage = "Unable to start streaming: \(error)"
                        showErrorAlert = true
                    }
                }
            }
        }
    }
}


#Preview {
    CreatureDetail(creature: .mock())
}

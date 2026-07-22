import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

struct CreatureDetail: View {

    @AppStorage("activeUniverse") private var activeUniverse: UniverseIdentifier = 1


    let server = CreatureServerClient.shared
    let eventLoop = EventLoop.shared
    // Removed @ObservedObject var appState = AppState.shared
    let creatureManager = CreatureManager.shared


    @State private var errorAlert: ErrorAlert?
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var currentActivity: Activity = .idle

    var creature: Creature

    @State private var isDoingServerStuff: Bool = false
    @State private var serverMessage: String = ""

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")

    var body: some View {
        #if os(tvOS)
            // Sensor data floats on a tinted Liquid Glass card over the tvOS background
            SensorData(creature: creature, showTitle: false)
                .padding(32)
                .glassEffect(
                    .regular.tint(.blue.opacity(0.15)),
                    in: .rect(cornerRadius: 32)
                )
                .padding(.top, 24)
                .padding(.horizontal, 36)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .task {
                    // Seed initial activity and subscribe to updates
                    currentActivity = await AppState.shared.getCurrentActivity
                    for await state in await AppState.shared.stateUpdates {
                        currentActivity = state.currentActivity
                    }
                }
                .errorAlert($errorAlert)
        #else
            VStack {
                SensorData(creature: creature)
            }
            .toolbar(id: "\(creature.name) creatureDetail") {
                ToolbarItem(id: "control", placement: .primaryAction) {
                    Button(action: {
                        toggleStreaming()
                    }) {
                        Image(
                            systemName: (currentActivity == .streaming)
                                ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .foregroundStyle((currentActivity == .streaming) ? .green : .primary)
                    }
                }
            }
            #if !os(tvOS)
                .toolbarRole(.editor)
            #endif
            .overlay {
                if isDoingServerStuff {
                    Text(serverMessage)
                        .font(.title)
                        .padding()
                        .background(Color.green.opacity(0.4))
                        .clipShape(.rect(cornerRadius: 10))
                }
            }
            .onDisappear {
                streamingTask?.cancel()
            }
            .navigationTitle(creature.name)
            #if os(macOS)
                .navigationSubtitle(generateStatusString())
            #endif
            .task {
                // Seed initial activity and subscribe to updates
                currentActivity = await AppState.shared.getCurrentActivity
                for await state in await AppState.shared.stateUpdates {
                    currentActivity = state.currentActivity
                }
            }
            .errorAlert($errorAlert)
        #endif
    }


    func generateStatusString() -> String {
        let status =
            "ID: \(creature.id), Offset: \(creature.channelOffset), Mouth Slot: \(creature.mouthSlot), Active Universe: \(activeUniverse)"
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
                isDoingServerStuff = false
                errorAlert = ErrorAlert(
                    title: "Server Error",
                    message: "Unable to stop playlist playback: \(value)")
            case .success(let value):
                logger.info("stopped! \(value)")
                serverMessage = value
                // Deliberate display, not a wait: leave the server's confirmation up
                // briefly before dropping the overlay.
                try? await Task.sleep(for: .seconds(4))
                isDoingServerStuff = false
            }
        }
    }


    func toggleStreaming() {
        Task {
            let appStateActivity = await AppState.shared.getCurrentActivity
            logger.info("Toggling streaming - current activity: \(appStateActivity.description)")

            if appStateActivity == .streaming {
                // Stop streaming
                let result = await creatureManager.stopStreaming()
                switch result {
                case .success:
                    logger.debug("Successfully stopped streaming")
                    await AppState.shared.setCurrentActivity(.idle)
                    currentActivity = .idle
                case .failure(let error):
                    logger.warning("Unable to stop streaming: \(error)")
                }
            } else if appStateActivity == .idle || appStateActivity == .connectingToServer {
                // Start streaming
                await AppState.shared.setCurrentActivity(.streaming)
                let result = await creatureManager.startStreamingToCreature(creatureId: creature.id)
                switch result {
                case .success(let message):
                    logger.info("Streaming started: \(message)")
                    currentActivity = .streaming
                case .failure(let error):
                    logger.warning("Unable to start streaming: \(error)")
                    // Revert state on failure
                    await AppState.shared.setCurrentActivity(.idle)
                    currentActivity = .idle
                }
            } else {
                errorAlert = ErrorAlert(
                    title: "Server Error",
                    message:
                        "Unable to start streaming while in the \(appStateActivity.description) state"
                )
            }
        }
    }
}


#Preview {
    CreatureDetail(creature: .mock())
}

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


    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var currentActivity: Activity = .idle

    var creature: Creature

    @State private var isDoingServerStuff: Bool = false
    @State private var serverMessage: String = ""

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")

    var body: some View {
        #if os(tvOS)
            ZStack {
                // Full-screen liquid glass effect
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    Text(creature.name)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .shadow(radius: 8)
                        .padding(.top, 36)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 36)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                    SensorData(creature: creature, showTitle: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                // Seed initial activity and subscribe to updates
                let initial = await AppState.shared.getCurrentActivity
                await MainActor.run { currentActivity = initial }
                for await state in await AppState.shared.stateUpdates {
                    await MainActor.run { currentActivity = state.currentActivity }
                }
            }
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
                        .foregroundColor((currentActivity == .streaming) ? .green : .primary)
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
            .task {
                // Seed initial activity and subscribe to updates
                let initial = await AppState.shared.getCurrentActivity
                await MainActor.run { currentActivity = initial }
                for await state in await AppState.shared.stateUpdates {
                    await MainActor.run { currentActivity = state.currentActivity }
                }
            }
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
                DispatchQueue.main.async {
                    errorMessage = "Unable to stop playlist playback: \(value)"
                    showErrorAlert = true
                }
            case .success(let value):
                logger.info("stopped! \(value)")
                serverMessage = value
            }

            try? await Task.sleep(nanoseconds: 4_000_000_000)
            isDoingServerStuff = false
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
                    await MainActor.run { currentActivity = .idle }
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
                    await MainActor.run { currentActivity = .streaming }
                case .failure(let error):
                    logger.warning("Unable to start streaming: \(error)")
                    // Revert state on failure
                    await AppState.shared.setCurrentActivity(.idle)
                    await MainActor.run { currentActivity = .idle }
                }
            } else {
                await MainActor.run {
                    errorMessage =
                        "Unable to start streaming while in the \(appStateActivity.description) state"
                    showErrorAlert = true
                }
            }
        }
    }
}


#Preview {
    CreatureDetail(creature: .mock())
}

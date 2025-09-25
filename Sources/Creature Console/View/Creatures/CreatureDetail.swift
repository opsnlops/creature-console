import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

struct CreatureDetail: View {

    @AppStorage("activeUniverse") private var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var currentActivity: Activity = .idle

    var creature: Creature

    @State private var isDoingServerStuff: Bool = false
    @State private var serverMessage: String = ""
    @Namespace private var glassNamespace

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SensorData(creature: creature)
                    .padding()
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            }
            .padding()
        }
        .toolbar {
            #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    GlassEffectContainer(spacing: 20) {
                        HStack(spacing: 12) {
                            NavigationLink(destination: InputTableView(creature: creature)) {
                                Image(systemName: "slider.horizontal.3")
                                    .padding(8)
                            }

                            Button(action: {
                                toggleStreaming()
                            }) {
                                Image(
                                    systemName: (currentActivity == .streaming)
                                        ? "gamecontroller.fill" : "gamecontroller"
                                )
                                .padding(8)
                            }
                            .glassEffect(
                                (currentActivity == .streaming)
                                    ? .regular.tint(Activity.streaming.tintColor).interactive()
                                    : .regular.interactive(),
                                in: .capsule
                            )
                            .glassEffectUnion(id: "toolbar", namespace: glassNamespace)
                        }
                        .animation(.easeInOut, value: currentActivity)
                    }
                }
            #else
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink(destination: InputTableView(creature: creature)) {
                        Image(systemName: "slider.horizontal.3")
                            .padding(8)
                    }
                    .help("View Input Configuration")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        toggleStreaming()
                    }) {
                        Label(
                            "Toggle Streaming",
                            systemImage: (currentActivity == .streaming)
                                ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .labelStyle(.iconOnly)
                        .padding(8)
                    }
                    .glassEffect(
                        (currentActivity == .streaming)
                            ? .regular.tint(Activity.streaming.tintColor).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                    .animation(.easeInOut, value: currentActivity)
                    .help("Toggle Streaming")
                }
            #endif
        }
        #if os(iOS)
            .toolbar(id: "global-bottom-status") {
                ToolbarItem(id: "status", placement: .bottomBar) {
                    BottomStatusToolbarContent()
                }
            }
        #endif
        .toolbarRole(.editor)
        .overlay {
            if isDoingServerStuff {
                Text(serverMessage)
                    .font(.title)
                    .padding()
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
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
        .task {
            // Keep local currentActivity in sync with global AppState
            for await state in await AppState.shared.stateUpdates {
                await MainActor.run {
                    currentActivity = state.currentActivity
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

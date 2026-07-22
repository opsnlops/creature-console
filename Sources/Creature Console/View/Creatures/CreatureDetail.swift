import Common
import Dispatch
import Foundation
import OSLog
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct CreatureDetail: View {

    @AppStorage("activeUniverse") private var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared

    @Environment(ConsoleStore.self) private var console

    @State private var errorAlert: ErrorAlert?
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var idleEnabled: Bool? = nil
    @State private var idleToggleInFlight: Bool = false
    private let systemCountersStore = SystemCountersStore.shared
    @State private var runtimeLastReceived: Date? = nil

    var creature: Creature

    @State private var isDoingServerStuff: Bool = false
    @State private var serverMessage: String = ""
    @Namespace private var glassNamespace

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureDetail")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SensorData(creature: creature)
                    #if os(tvOS)
                        .padding(8)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        .scaleEffect(0.7)
                    #else
                        .padding()
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    #endif
                CreatureRuntimeSummary(runtime: runtimeState, lastUpdated: runtimeLastReceived)
                    #if os(tvOS)
                        .padding(8)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        .scaleEffect(0.7)
                    #else
                        .padding()
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    #endif
            }
            #if os(tvOS)
                .padding(8)
            #else
                .padding()
            #endif
        }
        .bottomToolbarInset()
        .toolbar {
            #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    GlassEffectContainer(spacing: 20) {
                        HStack(spacing: 12) {
                            NavigationLink(destination: CreatureConfigDisplay(creature: creature)) {
                                Image(systemName: "slider.horizontal.3")
                                    .padding(8)
                            }
                            .help("View Creature Configuration")

                            Button(action: {
                                toggleStreaming()
                            }) {
                                Image(
                                    systemName: (console.currentActivity == .streaming)
                                        ? "gamecontroller.fill" : "gamecontroller"
                                )
                                .padding(8)
                            }
                            .glassEffect(
                                (console.currentActivity == .streaming)
                                    ? .regular.tint(Activity.streaming.tintColor).interactive()
                                    : .regular.interactive(),
                                in: .capsule
                            )
                            .help("Toggle Streaming")
                            Button(action: {
                                toggleIdleLoop()
                            }) {
                                Image(
                                    systemName: (idleEnabled ?? false)
                                        ? "moon.zzz.fill" : "moon.zzz"
                                )
                                .padding(8)
                            }
                            .glassEffect(
                                (idleEnabled ?? false)
                                    ? .regular.tint(.teal).interactive()
                                    : .regular.interactive(),
                                in: .capsule
                            )
                            .disabled(idleToggleInFlight || idleEnabled == nil)
                            .help("Toggle Idle Loop")
                            .padding(.leading, 6)
                            .glassEffectUnion(id: "toolbar", namespace: glassNamespace)
                        }
                        .animation(.easeInOut, value: console.currentActivity)
                    }
                }
            #else
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink(destination: CreatureConfigDisplay(creature: creature)) {
                        Image(systemName: "slider.horizontal.3")
                            .padding(8)
                    }
                    .help("View Creature Configuration")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        toggleStreaming()
                    }) {
                        Label(
                            "Toggle Streaming",
                            systemImage: (console.currentActivity == .streaming)
                                ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .labelStyle(.iconOnly)
                        .padding(8)
                    }
                    .glassEffect(
                        (console.currentActivity == .streaming)
                            ? .regular.tint(Activity.streaming.tintColor).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                    .animation(.easeInOut, value: console.currentActivity)
                    .help("Toggle Streaming")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        toggleIdleLoop()
                    }) {
                        Label(
                            "Toggle Idle Loop",
                            systemImage: (idleEnabled ?? false) ? "moon.zzz.fill" : "moon.zzz"
                        )
                        .labelStyle(.iconOnly)
                        .padding(8)
                    }
                    .glassEffect(
                        (idleEnabled ?? false)
                            ? .regular.tint(.teal).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                    .animation(.easeInOut, value: idleEnabled)
                    .disabled(idleToggleInFlight || idleEnabled == nil)
                    .padding(.leading, 6)
                    .help("Toggle Idle Loop")
                }
            #endif
        }
        .toolbarRole(.editor)
        .overlay {
            if isDoingServerStuff {
                Text(serverMessage)
                    #if os(tvOS)
                        .font(.headline)
                    #else
                        .font(.title)
                    #endif
                    .padding()
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
            }
        }
        .onDisappear {
            streamingTask?.cancel()
        }
        .onAppear {
            logger.debug("CreatureDetail appeared for \(creature.id)")
        }
        .task(id: creature.id) {
            await refreshIdleState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("IdleStateChanged")))
        {
            notification in
            guard let state = notification.object as? IdleStateChanged else { return }
            guard state.creatureId == creature.id else { return }
            idleEnabled = state.idleEnabled
        }
        // `initial: true` mirrors the old `$runtimeStates` publisher's replay-on-subscribe, so
        // runtime data that arrived before this view appeared still stamps a timestamp.
        .onChange(of: systemCountersStore.runtimeStates, initial: true) { _, states in
            guard states.contains(where: { $0.creatureId == creature.id }) else { return }
            runtimeLastReceived = Date()
        }
        .errorAlert($errorAlert)
        .navigationTitle(creature.name)
        #if os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
            .navigationSubtitle(generateStatusString())
        #endif

    }

    private var runtimeState: CreatureRuntime? {
        systemCountersStore.runtimeStates.first(where: { $0.creatureId == creature.id })?.runtime
    }

    func generateStatusString() -> String {
        let status =
            "ID: \(creature.id), Offset: \(creature.channelOffset), Mouth Slot: \(creature.mouthSlot), Active Universe: \(activeUniverse)"
        return status
    }

    func stopPlaylistPlayback() {

        logger.debug("stopping playlist playback on server")
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
                logger.debug("stopped! \(value)")
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
            // Single source of truth: CreatureManager owns the streamingCreature + AppState
            // transition (shared with Storyboards). Per-creature toggle — stops if this creature
            // is already live, otherwise starts/switches to it. The activity change flows back
            // to the UI through ConsoleStore, so there's nothing to mirror locally.
            _ = await CreatureManager.shared.toggleStreaming(to: creature.id)
        }
    }

    func refreshIdleState() async {
        logger.debug("Idle refresh starting for \(creature.id)")
        do {
            let result = try await server.getCreature(creatureId: creature.id)
            switch result {
            case .success(let remoteCreature):
                let serverIdleEnabled = remoteCreature.runtime?.idleEnabled
                logger.debug(
                    "Idle refresh for \(creature.id): runtime=\(remoteCreature.runtime != nil ? "yes" : "no") idle=\(serverIdleEnabled.map { "\($0)" } ?? "nil")"
                )
                idleEnabled = serverIdleEnabled
            case .failure(let error):
                logger.warning(
                    "Idle refresh failed for \(creature.id): \(error.localizedDescription)")
                errorAlert = ErrorAlert(
                    title: "Server Error",
                    message: "Unable to load idle state: \(error)")
            }
        } catch {
            logger.error("Idle refresh threw for \(creature.id): \(error.localizedDescription)")
            errorAlert = ErrorAlert(
                title: "Server Error",
                message: "Unable to load idle state: \(error.localizedDescription)")
        }
    }

    func updateIdleEnabled(_ enabled: Bool) {
        guard !idleToggleInFlight else { return }
        let previousValue = idleEnabled
        idleEnabled = enabled
        idleToggleInFlight = true

        Task {
            let result = await server.setIdleEnabled(creatureId: creature.id, enabled: enabled)
            idleToggleInFlight = false
            switch result {
            case .success(let updatedCreature):
                idleEnabled = updatedCreature.runtime?.idleEnabled ?? enabled
            case .failure(let error):
                idleEnabled = previousValue
                errorAlert = ErrorAlert(
                    title: "Server Error",
                    message: "Unable to update idle loop: \(error)")
            }
        }
    }

    func toggleIdleLoop() {
        guard let current = idleEnabled else { return }
        updateIdleEnabled(!current)
    }
}


#Preview {
    CreatureDetail(creature: .mock())
        .environment(ConsoleStore.shared)
}

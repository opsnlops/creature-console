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

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var currentActivity: Activity = .idle
    @State private var idleEnabled: Bool? = nil
    @State private var idleToggleInFlight: Bool = false
    @ObservedObject private var systemCountersStore = SystemCountersStore.shared
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
                            .padding(.leading, 6)
                            .glassEffectUnion(id: "toolbar", namespace: glassNamespace)
                        }
                        .animation(.easeInOut, value: currentActivity)
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
        .onReceive(systemCountersStore.$runtimeStates) { states in
            guard states.contains(where: { $0.creatureId == creature.id }) else { return }
            runtimeLastReceived = Date()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Server Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
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
                await MainActor.run {
                    errorMessage = "Unable to stop playlist playback: \(value)"
                    showErrorAlert = true
                }
            case .success(let value):
                logger.debug("stopped! \(value)")
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
            logger.debug("toggleStreaming called - AppState: \(appStateActivity.description)")

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
                    logger.debug("Successfully started streaming: \(message)")
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
                await MainActor.run {
                    idleEnabled = serverIdleEnabled
                }
            case .failure(let error):
                logger.warning(
                    "Idle refresh failed for \(creature.id): \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = "Unable to load idle state: \(error)"
                    showErrorAlert = true
                }
            }
        } catch {
            logger.error("Idle refresh threw for \(creature.id): \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Unable to load idle state: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    func updateIdleEnabled(_ enabled: Bool) {
        guard !idleToggleInFlight else { return }
        let previousValue = idleEnabled
        idleEnabled = enabled
        idleToggleInFlight = true

        Task {
            let result = await server.setIdleEnabled(creatureId: creature.id, enabled: enabled)
            await MainActor.run {
                idleToggleInFlight = false
                switch result {
                case .success(let updatedCreature):
                    idleEnabled = updatedCreature.runtime?.idleEnabled ?? enabled
                case .failure(let error):
                    idleEnabled = previousValue
                    errorMessage = "Unable to update idle loop: \(error)"
                    showErrorAlert = true
                }
            }
        }
    }

    func toggleIdleLoop() {
        guard let current = idleEnabled else { return }
        updateIdleEnabled(!current)
    }
}

private struct CreatureRuntimeSummary: View {
    let runtime: CreatureRuntime?
    let lastUpdated: Date?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Runtime")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let lastUpdated {
                    Text("Last updated: \(dateFormatter.string(from: lastUpdated))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if let runtime {
                runtimeDetails(runtime)
            } else {
                Text("Runtime data not available yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private func runtimeDetails(_ runtime: CreatureRuntime) -> some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 10) {
                runtimeSectionMac(
                    "Activity",
                    items: [
                        ("State", runtime.activity?.state.rawValue),
                        ("Reason", runtime.activity?.reason?.rawValue),
                        ("Animation ID", runtime.activity?.animationId),
                        ("Session ID", runtime.activity?.sessionId),
                        ("Started", formattedDate(runtime.activity?.startedAt)),
                        ("Updated", formattedDate(runtime.activity?.updatedAt)),
                    ]
                )

                runtimeSectionMac(
                    "Idle",
                    items: [
                        ("Enabled", runtime.idleEnabled.map { $0 ? "true" : "false" })
                    ]
                )

                runtimeSectionMac(
                    "Ownership",
                    items: [
                        ("BGM Owner", runtime.bgmOwner)
                    ]
                )

                if let lastError = runtime.lastError {
                    runtimeSectionMac(
                        "Last Error",
                        items: [
                            ("Message", lastError.message),
                            ("Timestamp", formattedDate(lastError.timestamp)),
                        ]
                    )
                }

                if let counters = runtime.counters {
                    runtimeSectionMac(
                        "Counters",
                        items: [
                            ("Sessions Started", counters.sessionsStartedTotal.map { "\($0)" }),
                            ("Sessions Cancelled", counters.sessionsCancelledTotal.map { "\($0)" }),
                            ("Idle Started", counters.idleStartedTotal.map { "\($0)" }),
                            ("Idle Stopped", counters.idleStoppedTotal.map { "\($0)" }),
                            ("Idle Toggles", counters.idleTogglesTotal.map { "\($0)" }),
                            (
                                "Skips Missing Creature",
                                counters.skipsMissingCreatureTotal.map { "\($0)" }
                            ),
                            ("BGM Takeovers", counters.bgmTakeoversTotal.map { "\($0)" }),
                            ("Audio Resets", counters.audioResetsTotal.map { "\($0)" }),
                        ]
                    )
                }
            }
        #else
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Activity")
                VStack(alignment: .leading, spacing: 8) {
                    runtimeRow("State", value: runtime.activity?.state.rawValue)
                    runtimeRow("Reason", value: runtime.activity?.reason?.rawValue)
                    runtimeRow("Animation ID", value: runtime.activity?.animationId)
                    runtimeRow("Session ID", value: runtime.activity?.sessionId)
                    runtimeRow("Started", value: formattedDate(runtime.activity?.startedAt))
                    runtimeRow("Updated", value: formattedDate(runtime.activity?.updatedAt))
                }

                sectionTitle("Idle")
                runtimeRow("Enabled", value: runtime.idleEnabled.map { $0 ? "true" : "false" })

                sectionTitle("Ownership")
                runtimeRow("BGM Owner", value: runtime.bgmOwner)

                if let lastError = runtime.lastError {
                    sectionTitle("Last Error")
                    VStack(alignment: .leading, spacing: 8) {
                        runtimeRow("Message", value: lastError.message)
                        runtimeRow("Timestamp", value: formattedDate(lastError.timestamp))
                    }
                }

                if let counters = runtime.counters {
                    sectionTitle("Counters")
                    VStack(alignment: .leading, spacing: 8) {
                        runtimeRow(
                            "Sessions Started",
                            value: counters.sessionsStartedTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Sessions Cancelled",
                            value: counters.sessionsCancelledTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Idle Started",
                            value: counters.idleStartedTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Idle Stopped",
                            value: counters.idleStoppedTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Idle Toggles",
                            value: counters.idleTogglesTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Skips Missing Creature",
                            value: counters.skipsMissingCreatureTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "BGM Takeovers",
                            value: counters.bgmTakeoversTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Audio Resets",
                            value: counters.audioResetsTotal.map { "\($0)" }
                        )
                    }
                }
            }
        #endif
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            #if os(macOS)
                .font(.caption)
            #else
                .font(.subheadline)
            #endif
            .foregroundStyle(.secondary)
    }

    private func runtimeRow(_ label: String, value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? "n/a")
        }
    }

    #if os(macOS)
        private var runtimeGridColumns: [GridItem] {
            [
                GridItem(.flexible(minimum: 140), alignment: .leading),
                GridItem(.flexible(minimum: 140), alignment: .leading),
            ]
        }

        @ViewBuilder
        private func runtimeSectionMac(_ title: String, items: [(String, String?)]) -> some View {
            sectionTitle(title)
            LazyVGrid(columns: runtimeGridColumns, alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.0)
                            .foregroundStyle(.secondary)
                        Text(item.1 ?? "n/a")
                    }
                    .font(.callout)
                }
            }
        }
    #endif

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.dateTime.hour().minute().second())
    }
}


#Preview {
    CreatureDetail(creature: .mock())
}

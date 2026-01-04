import Common
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct TopContentView: View {

    let appState = AppState.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared
    let messageProcessor = SwiftMessageProcessor.shared

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    @State var navigationPath = NavigationPath()

    @State private var selectedCreature: Creature?


    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TopContentView")


    var body: some View {
        #if os(iOS)
            if UIDevice.current.systemName == "iPadOS" {
                // iPad: Use floating toolbar
                ZStack(alignment: .bottom) {
                    navigationContent
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 100)
                        }
                    BottomToolBarView()
                }
            } else {
                // iPhone: Use native iOS toolbar
                navigationContent
                    .toolbar {
                        ToolbarItemGroup(placement: .bottomBar) {
                            iOSToolbarContent
                        }
                    }
            }
        #else
            // macOS/tvOS: Use floating toolbar
            ZStack(alignment: .bottom) {
                navigationContent
                BottomToolBarView()
            }
        #endif
    }

    @ViewBuilder
    private var navigationContent: some View {
        NavigationSplitView {
            List {
                Section("Creatures") {
                    if !creatures.isEmpty {
                        ForEach(creatures) { creature in
                            NavigationLink(value: creature.id) {
                                Label(creature.name, systemImage: "pawprint.circle")
                            }
                        }
                    } else {
                        Label("Loading...", systemImage: "server.rack")
                    }
                }

                #if os(tvOS)
                    Section("Live Magic") {
                        NavigationLink {
                            LiveMagicView()
                        } label: {
                            Label("Live Magic Console", systemImage: "sparkles.rectangle.stack")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }

                    Section("Animations") {
                        NavigationLink {
                            TVAnimationTriggerView()
                        } label: {
                            Label("Animation Triggers", systemImage: "figure.socialdance")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }

                    Section("Soundboard") {
                        NavigationLink {
                            TVSoundboardView()
                        } label: {
                            Label("Soundboard", systemImage: "speaker.wave.2")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                #elseif os(iOS) || os(macOS)
                    Section("Live Magic") {
                        NavigationLink {
                            LiveMagicView()
                        } label: {
                            Label("Live Magic Console", systemImage: "sparkles.rectangle.stack")
                                .symbolRenderingMode(.hierarchical)
                        }

                        NavigationLink {
                            AdHocAnimationListView()
                        } label: {
                            Label("Ad-Hoc Animations", systemImage: "film.stack")
                        }

                        NavigationLink {
                            AdHocSoundListView()
                        } label: {
                            Label("Ad-Hoc Sounds", systemImage: "waveform.circle")
                        }
                    }
                #endif


                #if os(iOS) || os(macOS)
                    Section("Animations") {
                        NavigationLink {
                            AnimationTable()
                        } label: {
                            Label("List All", systemImage: "figure.socialdance")
                        }
                        NavigationLink {
                            AnimationEditor(createNew: true)
                        } label: {
                            Label("Record New", systemImage: "hare")
                        }
                    }
                #endif

                #if os(iOS) || os(macOS)
                    Section("Playlists") {
                        NavigationLink {
                            PlaylistsTable()
                        } label: {
                            Label("List All", systemImage: "list.bullet.rectangle")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                #endif

                #if os(iOS) || os(macOS)
                    Section("Sound Files") {
                        NavigationLink {
                            SoundFileListView()
                        } label: {
                            Label("List All", systemImage: "music.note.list")
                        }
                        NavigationLink {
                            CreateNewCreatureSoundView()
                        } label: {
                            Label("Create New", systemImage: "waveform.path.badge.plus")
                                .symbolRenderingMode(.multicolor)
                        }
                    }
                #endif


                Section("Controls") {
                    NavigationLink {
                        JoystickDebugView()
                    } label: {
                        Label("Debug Joystick", systemImage: "gamecontroller")
                    }

                    #if os(iOS) || os(macOS)
                        NavigationLink {
                            LogView()
                        } label: {
                            Label("Server Logs", systemImage: "server.rack")
                        }
                    #endif

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }

                }
            }
            .navigationTitle("Creature Console")
            .navigationDestination(for: CreatureIdentifier.self) { creature in
                creatureDetailView(for: creature)
            }
            .task {
                await importFromServerIfNeeded()
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Oooooh Shit"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Fuck"))
                )
            }
        } detail: {
            NavigationStack(path: $navigationPath) {
                Text("Using server: \(server.getHostname())")
                    .padding()
                    .navigationDestination(for: CreatureIdentifier.self) { creatureID in
                        creatureDetailView(for: creatureID)
                    }
            }

        }
    }

    #if os(iOS)
        @ViewBuilder
        private var iOSToolbarContent: some View {
            iOSStatusLightsView()
        }
    #endif
}

#if os(iOS)
    struct iOSStatusLightsView: View {
        @State private var statusLightsState = StatusLightsState(
            running: false, dmx: false, streaming: false, animationPlaying: false)
        @State private var appState = AppStateData(
            currentActivity: .idle,
            currentAnimation: nil,
            selectedTrack: nil,
            showSystemAlert: false,
            systemAlertMessage: ""
        )
        @State private var websocketState: WebSocketConnectionState = .disconnected
        @Namespace private var glassNamespace

        var body: some View {
            HStack(spacing: 8) {
                // Activity indicator
                HStack(spacing: 4) {
                    Image(systemName: appState.currentActivity.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                    Text(appState.currentActivity.description)
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(
                    .regular
                        .tint(appState.currentActivity.tintColor.opacity(0.35))
                        .interactive(),
                    in: .capsule
                )
                .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)

                // WebSocket indicator
                HStack(spacing: 4) {
                    Image(systemName: websocketState.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                    Text(websocketState.description)
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(
                    .regular
                        .tint(websocketState.tintColor.opacity(0.35))
                        .interactive(),
                    in: .capsule
                )
                .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)

                Spacer()

                // Status lights
                HStack(spacing: 6) {
                    ForEach(StatusLightsState.allLights, id: \.self) { light in
                        Image(systemName: light.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                light.isActive(in: statusLightsState) ? .white : .secondary
                            )
                            .padding(6)
                            .glassEffect(
                                .regular
                                    .tint(
                                        light.tintColor.opacity(
                                            light.isActive(in: statusLightsState) ? 0.85 : 0.25)
                                    )
                                    .interactive(),
                                in: .circle
                            )
                            .glassEffectUnion(id: "statusLights", namespace: glassNamespace)
                            .scaleEffect(light.isActive(in: statusLightsState) ? 1.06 : 1.0)
                            .opacity(light.isActive(in: statusLightsState) ? 1.0 : 0.8)
                    }
                }
            }
            .task {
                for await state in await StatusLightsManager.shared.stateUpdates {
                    await MainActor.run {
                        statusLightsState = state
                    }
                }
            }
            .task { @MainActor in
                let initialActivity = await AppState.shared.getCurrentActivity
                appState = AppStateData(
                    currentActivity: initialActivity,
                    currentAnimation: appState.currentAnimation,
                    selectedTrack: appState.selectedTrack,
                    showSystemAlert: appState.showSystemAlert,
                    systemAlertMessage: appState.systemAlertMessage
                )

                let updates = await AppState.shared.stateUpdates
                for await state in updates {
                    appState = state
                }
            }
            .task { @MainActor in
                let initialWebSocketState = await WebSocketStateManager.shared.getCurrentState
                websocketState = initialWebSocketState

                for await state in await WebSocketStateManager.shared.stateUpdates {
                    guard !Task.isCancelled else { break }
                    websocketState = state
                }
            }
        }
    }
#endif

extension TopContentView {


    /**
     Show either the CreatureDetail view, or a blank one.
     */
    func creatureDetailView(for id: CreatureIdentifier) -> some View {
        if let creature = creatures.first(where: { $0.id == id }) {
            return AnyView(CreatureDetail(creature: creature.toDTO()))
        } else {
            return AnyView(EmptyView())
        }
    }

    private func importFromServerIfNeeded() async {
        // If we already have creatures, skip fetch
        if !creatures.isEmpty { return }
        do {
            let importer = CreatureImporter(modelContainer: modelContext.container)
            logger.debug("Fetching creature list from server for SwiftData import")
            let result = await server.getAllCreatures()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                logger.debug("Imported \(list.count) creatures into SwiftData")
            case .failure(let error):
                await MainActor.run {
                    errorMessage = ServerError.detailedMessage(from: error)
                    showErrorAlert = true
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Error importing creatures: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}

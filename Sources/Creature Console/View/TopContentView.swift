import Common
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct TopContentView: View {

    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared
    let messageProcessor = SwiftMessageProcessor.shared

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    @State private var errorAlert: ErrorAlert?

    @State var navigationPath = NavigationPath()

    @State private var selectedCreature: Creature?
    @State private var hideBottomToolbar = false


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
                if !hideBottomToolbar {
                    BottomToolBarView()
                }
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

                    Section("Diagnostics") {
                        NavigationLink {
                            TVSACNUniverseMonitorView()
                        } label: {
                            Label(
                                "sACN Universe Monitor",
                                systemImage: "dot.radiowaves.left.and.right"
                            )
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
                    Section("Dialogs") {
                        NavigationLink {
                            DialogScriptTable()
                        } label: {
                            Label("List All", systemImage: "text.bubble")
                        }
                        NavigationLink {
                            DialogScriptEditor(createNew: true)
                        } label: {
                            Label("Create New", systemImage: "plus.bubble")
                        }
                    }
                #endif

                #if os(iOS) || os(macOS)
                    Section("Storyboards") {
                        NavigationLink {
                            StoryboardTable()
                        } label: {
                            Label("List All", systemImage: "square.grid.2x2")
                        }
                        NavigationLink {
                            StoryboardEditor(createNew: true)
                        } label: {
                            Label("Create New", systemImage: "plus.square.on.square")
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
                    Section("Fixtures") {
                        NavigationLink {
                            FixturesTable()
                        } label: {
                            Label("List All", systemImage: "lightbulb.led")
                                .symbolRenderingMode(.hierarchical)
                        }
                        NavigationLink {
                            FixtureEditor(createNew: true)
                        } label: {
                            Label("Create New", systemImage: "plus.circle")
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
            // The floating BottomToolBarView overlaps the sidebar on iPad/macOS, hiding the last
            // rows (Settings). Reserve matching space so the whole list scrolls clear of it.
            #if os(macOS)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 110) }
            #elseif os(iOS)
                .safeAreaInset(edge: .bottom) {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Color.clear.frame(height: 110)
                    }
                }
            #endif
            .navigationDestination(for: CreatureIdentifier.self) { creature in
                creatureDetailView(for: creature)
            }
            .task {
                await importFromServerIfNeeded()
            }
            .errorAlert($errorAlert, dismissLabel: "Fuck")
        } detail: {
            NavigationStack(path: $navigationPath) {
                Text("Using server: \(server.getHostname())")
                    .padding()
                    .navigationDestination(for: CreatureIdentifier.self) { creatureID in
                        creatureDetailView(for: creatureID)
                    }
            }

        }
        .onPreferenceChange(HideBottomToolbarPreferenceKey.self) { hide in
            hideBottomToolbar = hide
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
        @Environment(ConsoleStore.self) private var console
        @Namespace private var glassNamespace

        var body: some View {
            // GlassEffectContainer lets the tinted chips and status dots morph/blend as a single
            // cluster, matching the macOS idiom in BottomStatusToolbarContent.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    // Activity indicator
                    HStack(spacing: 4) {
                        Image(systemName: console.currentActivity.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(console.currentActivity.description)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(
                        .regular
                            .tint(console.currentActivity.tintColor.opacity(0.35))
                            .interactive(),
                        in: .capsule
                    )
                    .glassEffectUnion(id: "statusCluster", namespace: glassNamespace)

                    // WebSocket indicator
                    HStack(spacing: 4) {
                        Image(systemName: console.websocketState.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(console.websocketState.description)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(
                        .regular
                            .tint(console.websocketState.tintColor.opacity(0.35))
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
                                    light.isActive(in: console.statusLights) ? .white : .secondary
                                )
                                .padding(6)
                                .glassEffect(
                                    .regular
                                        .tint(
                                            light.tintColor.opacity(
                                                light.isActive(in: console.statusLights)
                                                    ? 0.85 : 0.25)
                                        )
                                        .interactive(),
                                    in: .circle
                                )
                                .glassEffectUnion(id: "statusLights", namespace: glassNamespace)
                                .scaleEffect(light.isActive(in: console.statusLights) ? 1.06 : 1.0)
                                .opacity(light.isActive(in: console.statusLights) ? 1.0 : 0.8)
                        }
                    }
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
                errorAlert = ErrorAlert(title: "Oooooh Shit", error: error)
            }
        } catch {
            errorAlert = ErrorAlert(
                title: "Oooooh Shit",
                message: "Error importing creatures: \(error.localizedDescription)")
        }
    }
}

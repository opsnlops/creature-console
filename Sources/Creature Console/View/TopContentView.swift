import Common
import OSLog
import SwiftUI

struct TopContentView: View {

    let appState = AppState.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared
    let messageProcessor = SwiftMessageProcessor.shared

    // These do not need to be observed since we don't show the in the sidebar
    let animationMetadataCache = AnimationMetadataCache.shared
    let playlistCache = PlaylistCache.shared


    // Watch the cache to know what to do
    @ObservedObject private var creatureCache = CreatureCache.shared


    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    @State var navigationPath = NavigationPath()

    @State private var selectedCreature: Creature?


    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TopContentView")


    var body: some View {

        NavigationSplitView {
            List {
                Section("Creatures") {
                    if !creatureCache.empty {
                        ForEach(creatureCache.creatures.values.sorted(by: { $0.name < $1.name })) {
                            creature in
                            NavigationLink(value: creature.id) {
                                Label(creature.name, systemImage: "pawprint.circle")
                            }
                        }
                    } else {
                        Label("Loading...", systemImage: "server.rack")
                    }
                }


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
                            SoundFileTable()
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

                    #if os(iOS) || os(macOS)
                        NavigationLink {
                            AudioFilePicker()
                        } label: {
                            Label("Audio", systemImage: "hifispeaker.2")
                                .symbolRenderingMode(.hierarchical)
                        }
                    #endif
                }
            }
            .navigationTitle("Creature Console")
            .navigationDestination(for: CreatureIdentifier.self) { creature in
                creatureDetailView(for: creature)
            }
            .task {

                /**
                 Now that we're all loaded, let's go get the first set of creatures from the server
                 */

                let populateResult = await CreatureManager.shared.populateCache()
                switch populateResult {
                case .success(let message):

                    logger.info("Loaded the creature cache: \(message)")

                    // Okay! We're talking to the server. Bring up the websocket! 🧦
                    await server.connectWebsocket(processor: SwiftMessageProcessor.shared)

                case .failure(let error):
                    DispatchQueue.main.async {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }

                }

                // Now populate the animation metadata cache
                let animationResult = animationMetadataCache.fetchMetadataListFromServer()
                switch animationResult {
                case .success(let message):
                    logger.debug("populated the metadata cache: \(message)")
                case .failure(let error):
                    logger.warning("unable to fetch the metadata cache")
                    DispatchQueue.main.async {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }

                // And the playlist cache
                let playlistCacheResult = playlistCache.fetchPlaylistsFromServer()
                switch playlistCacheResult {
                case .success(let message):
                    logger.debug("populated the playlist cache: \(message)")
                case .failure(let error):
                    logger.warning("unable to fetch the playlist cache")
                    DispatchQueue.main.async {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }


            }.alert(isPresented: $showErrorAlert) {
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

        #if os(macOS) || os(tvOS)
            BottomToolBarView()
        #endif

        #if os(iOS)
            if UIDevice.current.systemName == "iPadOS" {
                BottomToolBarView()
            }
        #endif
    }


    /**
     Show either the CreatureDetail view, or a blank one.
     */
    func creatureDetailView(for id: CreatureIdentifier) -> some View {
        switch creatureCache.getById(id: id) {
        case .success(let creature):
            return AnyView(CreatureDetail(creature: creature))
        case .failure(let error):
            errorMessage = error.localizedDescription
            showErrorAlert = true
            return AnyView(EmptyView())
        }
    }
}

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
        ZStack(alignment: .bottom) {
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
            .safeAreaInset(edge: .bottom) {
                // Reserve space so content doesn't get completely hidden behind the floating bar
                Color.clear.frame(height: 100)
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
    }


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
            logger.info("Fetching creature list from server for SwiftData import")
            let result = await server.getAllCreatures()
            switch result {
            case .success(let list):
                try await importer.upsertBatch(list)
                logger.info("Imported \(list.count) creatures into SwiftData")
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

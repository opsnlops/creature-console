import Common
import OSLog
import SwiftUI

struct AnimationTable: View {
    let eventLoop = EventLoop.shared

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    var creature: Creature?

    @State private var animationCacheState = AnimationMetadataCacheState(
        metadatas: [:], empty: true)

    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var selection: AnimationMetadata.ID? = nil

    @State private var loadAnimationTask: Task<Void, Never>? = nil
    @State private var playAnimationTask: Task<Void, Never>? = nil

    @State private var navigateToEditor = false

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationTable")

    var body: some View {
        NavigationStack {
            VStack {
                if !animationCacheState.metadatas.isEmpty {
                    Table(of: AnimationMetadata.self, selection: $selection) {
                        TableColumn("Name", value: \.title)
                            .width(min: 120, ideal: 250)
                        TableColumn("Frames") { a in
                            Text(a.numberOfFrames, format: .number)
                        }
                        .width(60)
                        TableColumn("Period") { a in
                            Text("\(a.millisecondsPerFrame)ms")
                        }
                        .width(55)
                        TableColumn("Audio") { a in
                            Text(a.soundFile)
                        }
                        TableColumn("Time (ms)") { a in
                            Text(a.numberOfFrames * a.millisecondsPerFrame, format: .number)
                        }
                        .width(80)
                    } rows: {
                        ForEach(
                            animationCacheState.metadatas.values.sorted(by: { $0.title < $1.title })
                        ) { metadata in
                            TableRow(metadata)
                                .contextMenu {
                                    Button {
                                        print("play sound file selected")
                                    } label: {
                                        Label("Play Sound File", systemImage: "music.quarternote.3")
                                    }
                                    .disabled(metadata.soundFile.isEmpty)

                                    Button {
                                        playStoredAnimation(animationId: selection)
                                    } label: {
                                        Label("Play on Server", systemImage: "play")
                                            .foregroundColor(.green)
                                    }

                                    NavigationLink(
                                        destination: AnimationEditor(),
                                        label: {
                                            Label("Edit", systemImage: "pencil")
                                                .foregroundColor(.accentColor)
                                        })
                                }
                        }
                    }

                    Spacer()

                    // Buttons at the bottom
                    HStack {
                        //                        Button {
                        //                            // playAnimationLocally()
                        //                        } label: {
                        //                            Label("Play Locally", systemImage: "play.fill")
                        //                                .foregroundColor(.green)
                        //                        }
                        //                        .disabled(selection == nil)

                        Button {
                            playStoredAnimation(animationId: selection)
                        } label: {
                            Label("Play on Server", systemImage: "play")
                                .foregroundColor(.blue)
                        }
                        .disabled(selection == nil)

                        Button {
                            if let selection = selection {
                                loadAnimationToAppState(animationId: selection)
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .foregroundColor(.accentColor)
                        }
                        .disabled(selection == nil)
                    }  // Button bar HStack
                    .padding()
                } else {
                    ProgressView("Loading animations...")
                        .padding()
                }
            }  // VStack
            .onDisappear {
                loadAnimationTask?.cancel()
                playAnimationTask?.cancel()
            }
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .onChange(of: creature) {
                logger.info("onChange() in AnimationTable")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Unable to load Animations"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Fiiiiiine"))
                )
            }
            .navigationTitle("Animations")
            #if os(macOS)
                .navigationSubtitle("Number of Animations: \(animationCacheState.metadatas.count)")
            #endif
            .task {
                for await state in await AnimationMetadataCache.shared.stateUpdates {
                    await MainActor.run {
                        animationCacheState = state
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToEditor) {
                AnimationEditor()
            }
            .toolbar(id: "animationTableToolbar") {
                ToolbarItem(id: "newTrack", placement: .primaryAction) {
                    NavigationLink(
                        destination: AnimationEditor(createNew: true),
                        label: {
                            Label("Add Track", systemImage: "plus")
                        }
                    )
                }
            }
        }  // NavigationStack
    }  // body

    func loadAnimationToAppState(animationId: AnimationIdentifier) {
        loadAnimationTask?.cancel()

        loadAnimationTask = Task {
            let result = await server.getAnimation(animationId: animationId)
            switch result {
            case .success(let animation):
                await MainActor.run {
                    navigateToEditor = true
                }
                await AppState.shared.setCurrentAnimation(animation)
            case .failure(let error):
                alertMessage = "Error: \(error.localizedDescription)"
                logger.warning("Unable to load animation for editing: \(alertMessage)")
                showErrorAlert = true
            }
        }
    }

    func playStoredAnimation(animationId: AnimationIdentifier?) {
        guard let animationId = animationId else {
            logger.debug("playStoredAnimation was called with a nil selection")
            return
        }

        playAnimationTask?.cancel()

        let manager = creatureManager
        let universe = activeUniverse
        
        playAnimationTask = Task {
            let result = await manager.playStoredAnimationOnServer(
                animationId: animationId, universe: universe)
            switch result {
            case .success(let message):
                logger.info("Animation Scheduled: \(message)")
            case .failure(let error):
                logger.warning("Unable to schedule animation: \(error.localizedDescription)")
                alertMessage = "Unable to schedule animation: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}

struct AnimationTable_Previews: PreviewProvider {
    static var previews: some View {
        AnimationTable(creature: .mock())
    }
}

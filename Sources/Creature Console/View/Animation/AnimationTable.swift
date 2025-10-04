import Common
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct AnimationTable: View {
    let eventLoop = EventLoop.shared

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    var creature: Creature?

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]

    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var selection: AnimationIdentifier? = nil

    @State private var loadAnimationTask: Task<Void, Never>? = nil
    @State private var playAnimationTask: Task<Void, Never>? = nil

    @State private var navigateToEditor = false
    @State private var animationToEdit: Common.Animation? = nil

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationTable")

    var body: some View {
        NavigationStack {
            VStack {
                if !animations.isEmpty {
                    Table(animations, selection: $selection) {
                        TableColumn("Name") { a in
                            Text(a.title)
                                .onTapGesture(count: 2) {
                                    loadAnimationForEditing(animationId: a.id)
                                }
                        }
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
                    }
                    .contextMenu(forSelectionType: AnimationIdentifier.self) {
                        (items: Set<AnimationIdentifier>) in
                        // Determine if we have a selected ID (right-click updates selection automatically)
                        let hasSelection = (items.first ?? selection) != nil

                        Button {
                            playStoredAnimation(animationId: items.first ?? selection)
                        } label: {
                            Label("Play on Server", systemImage: "play")
                        }
                        .disabled(!hasSelection)

                        Button {
                            if let id = items.first ?? selection {
                                loadAnimationForEditing(animationId: id)
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .disabled(!hasSelection)

                        // Sound file action (kept as a stub; disabled when no sound file)
                        let hasSound: Bool = {
                            guard let id = items.first ?? selection,
                                let md = animations.first(where: { $0.id == id })
                            else { return false }
                            return !md.soundFile.isEmpty
                        }()
                        Button {
                            print("play sound file selected")
                        } label: {
                            Label("Play Sound File", systemImage: "music.quarternote.3")
                        }
                        .disabled(!hasSound)
                    }
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
                .navigationSubtitle("Number of Animations: \(animations.count)")
            #endif
            .navigationDestination(isPresented: $navigateToEditor) {
                if let animation = animationToEdit {
                    AnimationEditor(animation: animation)
                } else {
                    // Fallback: if somehow no animation is loaded, present create-new
                    AnimationEditor(createNew: true)
                }
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

    func loadAnimationForEditing(animationId: AnimationIdentifier) {
        loadAnimationTask?.cancel()

        loadAnimationTask = Task {
            let result = await server.getAnimation(animationId: animationId)
            switch result {
            case .success(let animation):
                await MainActor.run {
                    animationToEdit = animation
                    navigateToEditor = true
                }
            case .failure(let error):
                alertMessage = "Error: \(error.localizedDescription)"
                logger.warning("Unable to load animation for editing: \(alertMessage)")
                await MainActor.run { showErrorAlert = true }
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

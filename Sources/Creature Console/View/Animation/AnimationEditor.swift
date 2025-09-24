import Common
import OSLog
import SwiftUI

// This is the main animation editor for all of the Animations
struct AnimationEditor: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditor")

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared

    let eventLoop = EventLoop.shared
    let creatureManager = CreatureManager.shared


    // The parent view will set this to true if we're about to make a _new_ animation
    @State var createNew: Bool = false

    // Local animation state
    @State private var currentAnimation: Common.Animation?

    // Recording session management
    @State private var creatureCacheState = CreatureCacheState(creatures: [:], empty: true)
    @State private var availableCreatures: [Creature] = []
    @State private var showCreatureSelector = false

    // Local animation metadata state for binding
    @State private var animationTitle = ""
    @State private var animationSoundFile = ""
    @State private var animationNotes = ""
    @State private var animationMultitrackAudio = false
    @State private var animationMillisecondsPerFrame: UInt32 = 20

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    @State private var isSaving: Bool = false
    @State private var savingMessage: String = ""

    @State private var selectedCreatureForRecording: Creature? = nil
    // Removed @State private var navPath = NavigationPath()
    // Removed @State private var navigateToRecord: Bool = false

    // Initializers
    init() {
        self.createNew = false
    }

    init(createNew: Bool) {
        self.createNew = createNew
        if createNew {
            self._currentAnimation = State(initialValue: Common.Animation())
        }
    }

    init(animation: Common.Animation) {
        self.createNew = false
        self._currentAnimation = State(initialValue: animation)
    }


    var body: some View {
        NavigationStack {
            VStack {
                if currentAnimation != nil {
                    if createNew {
                        // New animation workflow - show comprehensive setup
                        newAnimationWorkflowView
                    } else {
                        // Existing animation editing
                        existingAnimationEditingView
                    }
                } else if createNew {
                    // Show loading while preparing new animation
                    VStack {
                        ProgressView()
                        Text("Preparing new animation...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(40)
                    .task {
                        logger.debug("New animation view loaded, currentAnimation: \(currentAnimation != nil ? "present" : "nil")")
                        loadAnimationMetadata()
                    }
                } else {
                    // No animation loaded
                    Text("No animation loaded")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(createNew ? "Record New Animation" : "Animation Editor")
            #if os(macOS)
                .navigationSubtitle("Active Universe: \(activeUniverse)")
            #endif
            .toolbar(id: "animationEditor") {
                ToolbarItem(id: "save", placement: .secondaryAction) {
                    Button(action: {
                        saveAnimationToServer()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .symbolRenderingMode(.palette)
                    }
                }
                ToolbarItem(id: "play", placement: .secondaryAction) {
                    Button(action: {
                        _ = playAnimation()
                    }) {
                        Image(systemName: "play.fill")
                    }
                }

                ToolbarItem(id: "newTrack", placement: .primaryAction) {
                    if currentAnimation != nil {
                        Menu {
                            if availableCreatures.isEmpty {
                                Label("No creatures available", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                                    .disabled(true)
                            } else {
                                ForEach(availableCreatures) { creature in
                                    Button {
                                        selectedCreatureForRecording = creature
                                    } label: {
                                        Label(creature.name, systemImage: "record.circle")
                                    }
                                }
                            }
                        } label: {
                            Label("Add Track", systemImage: "waveform.path.badge.plus")
                                .symbolRenderingMode(.multicolor)
                        }
                        .disabled(animationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button(action: {
                            logger.debug("Add Track button pressed - creatures: \(availableCreatures.count), animation: \(currentAnimation != nil ? "present" : "nil")")
                        }) {
                            Label("Add Track", systemImage: "waveform.path.badge.plus")
                                .symbolRenderingMode(.multicolor)
                        }
                        .disabled(true)
                    }
                }
            }
            .task {
                // First, get the current state immediately (so toolbar enables correctly)
                let currentState = await CreatureCache.shared.getCurrentState()
                await MainActor.run {
                    creatureCacheState = currentState
                    availableCreatures = Array(currentState.creatures.values).sorted { $0.name < $1.name }
                }

                // Load creature data
                for await state in await CreatureCache.shared.stateUpdates {
                    await MainActor.run {
                        creatureCacheState = state
                        availableCreatures = Array(state.creatures.values).sorted {
                            $0.name < $1.name
                        }
                        logger.debug("Loaded \(availableCreatures.count) creatures")
                    }
                }
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Oooooh Shit"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Fuck"))
                )
            }
            .overlay {
                if isSaving {
                    Text(savingMessage)
                        .font(.title)
                        .padding()
                        .background(Color.green.opacity(0.4))
                        .cornerRadius(10)
                }
            }
            .navigationDestination(item: $selectedCreatureForRecording) { creature in
                RecordTrack(creature: creature, localAnimation: currentAnimation)
            }
        }
    }


    func playAnimation() -> Result<String, AnimationError> {

        logger.info("play button pressed!")

        //        Task {
        //            if let a = animation {
        //
        //                let result =  await creatureManager.playAnimationLocally(animation: a, universe: activeUniverse)
        //                switch(result) {
        //                case (.failure(let message)):
        //                    logger.error("Unable to play animation: \(message))")
        //                default:
        //                    break
        //                }
        //            }
        //        }

        return .success("Queued up animation to play")
    }


    private func updateAnimationMetadata() {
        guard let animation = currentAnimation else { return }

        animation.metadata.title = animationTitle
        animation.metadata.soundFile = animationSoundFile
        animation.metadata.note = animationNotes
        animation.metadata.multitrackAudio = animationMultitrackAudio
        animation.metadata.millisecondsPerFrame = animationMillisecondsPerFrame
    }

    private func loadAnimationMetadata() {
        guard let animation = currentAnimation else { return }

        animationTitle = animation.metadata.title
        animationSoundFile = animation.metadata.soundFile
        animationNotes = animation.metadata.note
        animationMultitrackAudio = animation.metadata.multitrackAudio
        animationMillisecondsPerFrame = animation.metadata.millisecondsPerFrame
    }

    func saveAnimationToServer() {
        guard let animation = currentAnimation else { return }

        savingMessage = "Saving animation to server..."
        isSaving = true
        Task {
            let result = await server.saveAnimation(animation: animation)

            await MainActor.run {
                switch result {
                case .success(let data):
                    savingMessage = data
                    logger.debug("success!")

                case .failure(let error):
                    errorMessage = "Error: \(error.localizedDescription))"
                    showErrorAlert = true
                    logger.error(
                        "Unable to save animation to server: \(error.localizedDescription)")
                }
            }

            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {}

            await MainActor.run {
                isSaving = false
            }
        }
    }


    // MARK: - View Components

    private var newAnimationWorkflowView: some View {
        VStack(spacing: 20) {
            // Animation metadata section
            animationMetadataForm

            // Recording instructions
            recordingInstructionsView

            // Creatures section
            if !availableCreatures.isEmpty {
                creatureRecordingSection
            }

            // Show recorded tracks for the current animation
            TrackListingView(animation: currentAnimation)

            Spacer()
        }
        .padding()
    }

    private var existingAnimationEditingView: some View {
        VStack {
            animationMetadataForm
            TrackListingView(animation: currentAnimation)
            Spacer()
        }
    }

    private var animationMetadataForm: some View {
        Form {
            TextField("Title", text: $animationTitle)
                .textFieldStyle(.roundedBorder)
                .onChange(of: animationTitle) {
                    updateAnimationMetadata()
                }

            TextField("Sound File", text: $animationSoundFile)
                .textFieldStyle(.roundedBorder)
                .onChange(of: animationSoundFile) {
                    updateAnimationMetadata()
                }

            Toggle("Multi-Track Audio", isOn: $animationMultitrackAudio)
                .onChange(of: animationMultitrackAudio) {
                    updateAnimationMetadata()
                }

            TextField("Notes", text: $animationNotes)
                .textFieldStyle(.roundedBorder)
                .onChange(of: animationNotes) {
                    updateAnimationMetadata()
                }
        }
        .padding()
    }

    private var recordingInstructionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Recording Workflow")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Fill out animation details above")
                Text("2. Select creatures to record tracks for")
                Text("3. Record each creature's movement track")
                Text("4. Save the complete animation to server")
            }
            .font(.body)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var creatureRecordingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Tracks")
                .font(.headline)

            Text("Select creatures to record movement tracks:")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 200))
                ], spacing: 12
            ) {
                ForEach(availableCreatures) { creature in
                    CreatureRecordingCardView(
                        creature: creature,
                        hasTrack: hasTrackForCreature(creature.id),
                        animation: currentAnimation
                    )
                }
            }
        }
    }

    private func hasTrackForCreature(_ creatureId: CreatureIdentifier) -> Bool {
        return currentAnimation?.tracks.contains { $0.creatureId == creatureId } ?? false
    }


}

// MARK: - Supporting Views

struct CreatureRecordingCardView: View {
    let creature: Creature
    let hasTrack: Bool
    let animation: Common.Animation?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(creature.name)
                    .font(.headline)
                Spacer()
                if hasTrack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            Text("Channel \(creature.channelOffset)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let track = animation?.tracks.first(where: { $0.creatureId == creature.id }) {
                Text("\(track.frames.count) frames recorded")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            NavigationLink(destination: RecordTrack(creature: creature, localAnimation: animation))
            {
                if hasTrack {
                    Label("Re-record Track", systemImage: "arrow.clockwise")
                } else {
                    Label("Record Track", systemImage: "record.circle")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    hasTrack ? Color.green : .secondary,
                    lineWidth: hasTrack ? 2 : 1)
        )
        .cornerRadius(8)
    }


}


struct AnimationEditor_Previews: PreviewProvider {
    static var previews: some View {
        AnimationEditor()
    }
}


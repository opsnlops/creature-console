import Common
import OSLog
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// This is the main animation editor for all of the Animations
struct AnimationEditor: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditor")

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared


    // The parent view will set this to true if we're about to make a _new_ animation
    @State var createNew: Bool = false

    // Local animation state
    @StateObject private var model: AnimationEditorViewModel = AnimationEditorViewModel(
        animation: Common.Animation())

    @State private var availableCreatures: [Creature] = []


    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    @State private var isSaving: Bool = false
    @State private var savingMessage: String = ""

    @State private var selectedCreatureForRecording: Creature? = nil


    // Initializers
    init() {
        self.createNew = false
        self._model = StateObject(
            wrappedValue: AnimationEditorViewModel(animation: Common.Animation()))
    }

    init(createNew: Bool) {
        self.createNew = createNew
        self._model = StateObject(
            wrappedValue: AnimationEditorViewModel(animation: Common.Animation()))
    }

    init(animation: Common.Animation) {
        self.createNew = false
        self._model = StateObject(wrappedValue: AnimationEditorViewModel(animation: animation))
    }


    var body: some View {
        NavigationStack {
            VStack {
                if createNew {
                    // New animation workflow - show comprehensive setup
                    newAnimationWorkflowView
                } else {
                    // Existing animation editing
                    existingAnimationEditingView
                }
            }
            .onAppear {
                model.syncFromAnimation()
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
                    Menu {
                        if availableCreatures.isEmpty {
                            Label(
                                "No creatures available",
                                systemImage: "exclamationmark.triangle"
                            )
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
                    .disabled(model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                // First, get the current state immediately (so toolbar enables correctly)
                let currentState = await CreatureCache.shared.getCurrentState()
                await MainActor.run {
                    availableCreatures = Array(currentState.creatures.values).sorted {
                        $0.name < $1.name
                    }
                }

                // Load creature data
                for await state in await CreatureCache.shared.stateUpdates {
                    await MainActor.run {
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
                        .font(.title3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(.green), in: .capsule)
                }
            }
            .navigationDestination(item: $selectedCreatureForRecording) { creature in
                RecordTrack(creature: creature, localAnimation: model.animation) { track in
                    model.appendTrack(track)
                    model.syncFromAnimation()
                }
                .task {
                    // Align event loop/recording cadence with the animation's frame period
                    UserDefaults.standard.set(
                        Int(model.millisecondsPerFrame), forKey: "eventLoopMillisecondsPerFrame")
                }
            }
            #if os(iOS)
                .toolbar(id: "global-bottom-status") {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        ToolbarItem(id: "status", placement: .bottomBar) {
                            BottomStatusToolbarContent()
                        }
                    }
                }
            #endif
        }
    }


    func playAnimation() -> Result<String, AnimationError> {

        logger.info("play button pressed!")

        return .success("Queued up animation to play")
    }


    func saveAnimationToServer() {
        let animation = model.animation

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
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    // Animation metadata section
                    animationMetadataForm

                    // Recording instructions
                    recordingInstructionsView

                    // Creatures section
                    if !availableCreatures.isEmpty {
                        creatureRecordingSection
                    }

                    // Show recorded tracks for the current animation
                    TrackListingView(animation: model.animation)
                        .id(model.tracksVersion)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }

    private var existingAnimationEditingView: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    animationMetadataForm
                    TrackListingView(animation: model.animation)
                        .id(model.tracksVersion)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }

    private var animationMetadataForm: some View {
        Form {
            TextField("Title", text: $model.title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.title) { _ in
                    model.updateMetadataFromFields()
                }

            TextField("Sound File", text: $model.soundFile)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.soundFile) { _ in
                    model.updateMetadataFromFields()
                }

            Toggle("Multi-Track Audio", isOn: $model.multitrackAudio)
                .onChange(of: model.multitrackAudio) { _ in
                    model.updateMetadataFromFields()
                }

            HStack {
                Text("Frame Period (ms)")
                Spacer()
                Stepper(value: $model.millisecondsPerFrame, in: 5...100, step: 1) {
                    Text("\(model.millisecondsPerFrame) ms")
                }
            }
            .onChange(of: model.millisecondsPerFrame) { _ in
                model.updateMetadataFromFields()
            }

            TextField("Notes", text: $model.note)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.note) { _ in
                    model.updateMetadataFromFields()
                }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .center)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
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
                        animation: model.animation,
                        onTrackSaved: { track in
                            model.appendTrack(track)
                            model.syncFromAnimation()
                        }
                    )
                }
            }
        }
    }

    private func hasTrackForCreature(_ creatureId: CreatureIdentifier) -> Bool {
        return model.animation.tracks.contains { $0.creatureId == creatureId }
    }


}

// MARK: - Supporting Views

struct CreatureRecordingCardView: View {
    let creature: Creature
    let hasTrack: Bool
    let animation: Common.Animation?
    let onTrackSaved: ((Track) -> Void)?

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

            NavigationLink(
                destination: RecordTrack(
                    creature: creature,
                    localAnimation: animation,
                    onTrackSaved: onTrackSaved
                )
            ) {
                if hasTrack {
                    Label("Re-record Track", systemImage: "arrow.clockwise")
                } else {
                    Label("Record Track", systemImage: "record.circle")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }


}


struct AnimationEditor_Previews: PreviewProvider {
    static var previews: some View {
        AnimationEditor()
    }
}

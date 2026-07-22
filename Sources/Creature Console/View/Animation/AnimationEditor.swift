import Common
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

// This is the main animation editor for all of the Animations
struct AnimationEditor: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditor")

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared
    let readOnly: Bool

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    // The parent view will set this to true if we're about to make a _new_ animation
    @State var createNew: Bool = false

    // Local animation state
    @StateObject private var model: AnimationEditorViewModel

    @State private var availableCreatures: [Creature] = []


    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    @State private var showStatusOverlay: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusOverlayGeneration = 0

    @State private var playAnimationTask: Task<Void, Never>? = nil

    @State private var selectedCreatureForRecording: Creature? = nil

    /// Dialog provenance (script + per-creature mouth cues) for this animation's rendered sound,
    /// fetched lazily. Nil for hand-made animations or when the sound carries none.
    @State private var provenance: DialogProvenance? = nil


    // Initializers
    init() {
        self.createNew = false
        self.readOnly = false
        self._model = StateObject(
            wrappedValue: AnimationEditorViewModel(animation: Common.Animation()))
    }

    init(createNew: Bool) {
        self.createNew = createNew
        self.readOnly = false
        self._model = StateObject(
            wrappedValue: AnimationEditorViewModel(animation: Common.Animation()))
    }

    init(animation: Common.Animation, readOnly: Bool = false) {
        self.createNew = false
        self.readOnly = readOnly
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
            // Load the dialog provenance for the mouth-activity ribbons + per-track script. Keyed
            // on the sound file so an in-place re-render (which can swap the file) refetches.
            .task(id: model.animation.metadata.soundFile) {
                await loadProvenance()
            }
            .navigationTitle(createNew ? "Record New Animation" : "Animation Editor")
            #if os(macOS)
                .navigationSubtitle("Active Universe: \(activeUniverse)")
            #endif
            .toolbar(id: "animationEditor") {
                if !readOnly {
                    ToolbarItem(id: "save", placement: .secondaryAction) {
                        Button(action: {
                            saveAnimationToServer()
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .symbolRenderingMode(.palette)
                        }
                    }
                }
                ToolbarItem(id: "play", placement: .secondaryAction) {
                    Button(action: {
                        playAnimationOnServer()
                    }) {
                        Image(systemName: "play.fill")
                    }
                    // A brand-new animation doesn't exist on the server until it's saved,
                    // and the server is the only place animations play.
                    .disabled(createNew)
                    .help("Play on Server (Universe \(activeUniverse))")
                }

                if !readOnly {
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
                        .disabled(
                            model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onChange(of: creatures) { _, newCreatures in
                availableCreatures = newCreatures.map { $0.toDTO() }
                logger.debug("Loaded \(availableCreatures.count) creatures from SwiftData")
            }
            .onAppear {
                availableCreatures = creatures.map { $0.toDTO() }
            }
            .onDisappear {
                playAnimationTask?.cancel()
                playAnimationTask = nil
            }
            .alert(
                "Oooooh Shit", isPresented: $showErrorAlert,
                actions: {
                    Button("Fuck", role: .cancel) {}
                },
                message: {
                    Text(errorMessage)
                }
            )
            .overlay {
                if showStatusOverlay {
                    Text(statusMessage)
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
                    await MainActor.run {
                        UserDefaults.standard.set(
                            Int(model.millisecondsPerFrame),
                            forKey: "eventLoopMillisecondsPerFrame"
                        )
                    }
                }
            }
        }
    }


    /// Fetch the dialog provenance for the current sound file, if any. Driven by the **sound file's
    /// embedded iXML**, not the animation metadata's script pointer — a dialog render carries the
    /// lipsync/word alignment in the WAV even when `source_script_id` was never stamped on the
    /// animation (as happens for some renders). A 404 (no embedded provenance — e.g. a hand-made
    /// animation) is expected and simply clears the ribbons.
    private func loadProvenance() async {
        let soundFile = model.animation.metadata.soundFile
        guard !soundFile.isEmpty else {
            provenance = nil
            return
        }
        let result = await server.fetchDialogProvenance(fileName: soundFile)
        // If this fetch was superseded (the sound file changed and SwiftUI cancelled us) don't
        // clobber the newer fetch's result with this stale one.
        guard !Task.isCancelled, soundFile == model.animation.metadata.soundFile else { return }
        await MainActor.run {
            switch result {
            case .success(let fetched):
                provenance = fetched
            case .failure:
                provenance = nil
            }
        }
    }


    /// Schedule this animation for playback on the server. Animations only ever play on the
    /// server, so this plays the animation as last saved there — unsaved edits in the editor
    /// aren't reflected until the next save.
    func playAnimationOnServer() {
        let animationId = model.animation.id
        let universe = activeUniverse

        playAnimationTask?.cancel()
        playAnimationTask = Task {
            let result = await CreatureManager.shared.playStoredAnimationOnServer(
                animationId: animationId, universe: universe)

            await MainActor.run {
                switch result {
                case .success(let message):
                    logger.debug("Animation scheduled: \(message)")
                    showStatusBanner("Universe \(universe): \(message)")

                case .failure(let error):
                    let message = ServerError.detailedMessage(from: error)
                    logger.warning("Unable to schedule animation: \(message)")
                    errorMessage = message
                    showErrorAlert = true
                }
            }
        }
    }


    func saveAnimationToServer() {
        let animation = model.animation

        statusMessage = "Saving animation to server..."
        showStatusOverlay = true
        Task {
            let result = await server.saveAnimation(animation: animation)

            await MainActor.run {
                switch result {
                case .success(let data):
                    logger.debug("success!")
                    showStatusBanner(data)

                case .failure(let error):
                    let message = ServerError.detailedMessage(from: error)
                    showStatusOverlay = false
                    errorMessage = message
                    showErrorAlert = true
                    logger.error("Unable to save animation to server: \(message)")
                }
            }
        }
    }

    /// Show a transient status message in the glass overlay, auto-dismissing after a few
    /// seconds. The generation counter keeps an earlier banner's dismissal from cutting a
    /// newer one short.
    @MainActor
    private func showStatusBanner(_ message: String) {
        statusOverlayGeneration += 1
        let generation = statusOverlayGeneration
        statusMessage = message
        showStatusOverlay = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard generation == statusOverlayGeneration else { return }
            showStatusOverlay = false
        }
    }


    // MARK: - View Components

    @ViewBuilder
    private var animationMetadataFields: some View {
        TextField("Title", text: $model.title)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.title, initial: false) { _, _ in
                model.updateMetadataFromFields()
            }

        TextField("Sound File", text: $model.soundFile)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.soundFile, initial: false) { _, _ in
                model.updateMetadataFromFields()
            }

        Toggle("Multi-Track Audio", isOn: $model.multitrackAudio)
            .onChange(of: model.multitrackAudio, initial: false) { _, _ in
                model.updateMetadataFromFields()
            }

        HStack {
            Text("Frame Period (ms)")
            Spacer()
            Stepper(value: $model.millisecondsPerFrame, in: 5...100, step: 1) {
                Text("\(model.millisecondsPerFrame) ms")
            }
        }
        .onChange(of: model.millisecondsPerFrame, initial: false) { _, _ in
            model.updateMetadataFromFields()
        }

        TextField("Notes", text: $model.note)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.note, initial: false) { _, _ in
                model.updateMetadataFromFields()
            }
    }

    private var animationMetadataForm: some View {
        #if os(iOS)
            VStack(alignment: .leading, spacing: 12) {
                animationMetadataFields
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.horizontal)
        #else
            Form {
                animationMetadataFields
            }
            .formStyle(.grouped)
            .frame(maxWidth: 640)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .center)
        #endif
    }


    private var newAnimationWorkflowView: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    // Animation metadata section
                    animationMetadataForm

                    // Show recorded tracks for the current animation
                    TrackListingView(animation: model.animation)
                        .id(model.tracksVersion)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .bottomToolbarInset()
    }

    private var existingAnimationEditingView: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    animationMetadataForm
                    AnimationDialogProvenanceView(
                        metadata: model.animation.metadata,
                        onRerendered: { updated in model.reload(with: updated) }
                    )
                    TrackListingView(animation: model.animation, provenance: provenance)
                        .id(model.tracksVersion)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .bottomToolbarInset()
    }


    // MARK: - Supporting Views

    private func hasTrackForCreature(_ creatureId: CreatureIdentifier) -> Bool {
        return model.animation.tracks.contains { $0.creatureId == creatureId }
    }


}

struct AnimationEditor_Previews: PreviewProvider {
    static var previews: some View {
        AnimationEditor()
    }
}

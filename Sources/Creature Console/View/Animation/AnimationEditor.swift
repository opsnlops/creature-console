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
            .onChange(of: creatures) { _, newCreatures in
                availableCreatures = newCreatures.map { $0.toDTO() }
                logger.debug("Loaded \(availableCreatures.count) creatures from SwiftData")
            }
            .onAppear {
                availableCreatures = creatures.map { $0.toDTO() }
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
                    errorMessage = "Error: \(error.localizedDescription)"
                    showErrorAlert = true
                    logger.error(
                        "Unable to save animation to server: \(error.localizedDescription)")
                }
            }

            try? await Task.sleep(for: .seconds(2))

            await MainActor.run {
                isSaving = false
            }
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

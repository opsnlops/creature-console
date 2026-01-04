import Common
import OSLog
import SwiftData
import SwiftUI

/// The main coordinator for recording complete animations with multiple tracks
/// This handles the complete workflow from creation to save
struct AnimationRecordingCoordinator: View {

    let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationRecordingCoordinator")

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    // Core dependencies
    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    // State management
    @State private var appState = AppStateData(
        currentActivity: .idle,
        currentAnimation: nil,
        selectedTrack: nil,
        showSystemAlert: false,
        systemAlertMessage: ""
    )

    // Recording session state
    @State private var recordingSession: AnimationRecordingSession?
    @State private var currentWorkingAnimation: Common.Animation?

    // UI state
    @State private var showMetadataEditor = false
    @State private var showCreatureSelector = false
    @State private var selectedCreatureId: CreatureIdentifier?
    @State private var isRecordingTrack = false
    @State private var currentRecordingCreature: Creature?

    // Error handling
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    // Saving state
    @State private var isSaving = false
    @State private var savingMessage = ""

    var body: some View {
        VStack {
            if let session = recordingSession {
                AnimationRecordingSessionView(session: session)
            } else {
                // Initial setup view
                createNewAnimationView
            }
        }
        .navigationTitle("Record Animation")
        #if os(macOS)
            .navigationSubtitle("Universe \(activeUniverse)")
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if recordingSession != nil {
                    Button("Save Animation") {
                        saveAnimationToServer()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task {
            // Subscribe to state updates
            for await state in await AppState.shared.stateUpdates {
                await MainActor.run {
                    appState = state
                    handleAppStateChange(state)
                }
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Recording Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if isSaving {
                VStack {
                    ProgressView()
                    Text(savingMessage)
                        .font(.headline)
                        .padding(.top, 8)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 10)
            }
        }
    }

    private var createNewAnimationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Create New Animation")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Record creature movements and create synchronized animations")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                createNewRecordingSession()
            }) {
                Label("Start Recording Session", systemImage: "record.circle")
                    .font(.title2)
                    .padding()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(40)
    }

    private func createNewRecordingSession() {
        logger.debug("Creating new recording session")

        // Create new animation
        let newAnimation = Common.Animation()
        currentWorkingAnimation = newAnimation

        // Set it as current animation in AppState
        Task {
            await AppState.shared.setCurrentAnimation(newAnimation)
        }

        // Create recording session
        recordingSession = AnimationRecordingSession(
            animation: newAnimation,
            availableCreatures: creatures.map { $0.toDTO() }
        )

        logger.debug("Created new recording session for animation: \(newAnimation.id)")
    }

    private func handleAppStateChange(_ state: AppStateData) {
        // React to state changes if needed
        if let animation = state.currentAnimation {
            currentWorkingAnimation = animation
            recordingSession?.updateAnimation(animation)
        }
    }

    private func saveAnimationToServer() {
        guard let animation = currentWorkingAnimation else {
            errorMessage = "No animation to save"
            showErrorAlert = true
            return
        }

        savingMessage = "Saving animation to server..."
        isSaving = true

        Task {
            logger.debug("Saving animation '\(animation.metadata.title)' to server")

            let result = await server.saveAnimation(animation: animation)

            await MainActor.run {
                switch result {
                case .success(let message):
                    savingMessage = "Saved successfully!"
                    logger.debug("Animation saved: \(message)")

                case .failure(let error):
                    isSaving = false
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    showErrorAlert = true
                    logger.error("Save failed: \(error.localizedDescription)")
                    return
                }
            }

            // Show success for 2 seconds
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {}

            await MainActor.run {
                isSaving = false
            }
        }
    }
}

// MARK: - Recording Session Model

/// Manages the state of a recording session for an animation
@MainActor
class AnimationRecordingSession: ObservableObject {
    let id = UUID()

    @Published var animation: Common.Animation
    @Published var availableCreatures: [Creature]
    @Published var recordedTracks: [CreatureIdentifier: Track] = [:]
    @Published var currentRecordingCreature: CreatureIdentifier?
    @Published var sessionState: RecordingSessionState = .setup

    enum RecordingSessionState {
        case setup
        case recording
        case reviewing
        case completed
    }

    init(animation: Common.Animation, availableCreatures: [Creature]) {
        self.animation = animation
        self.availableCreatures = availableCreatures
    }

    func updateAnimation(_ animation: Common.Animation) {
        self.animation = animation
    }

    func addTrack(_ track: Track, for creatureId: CreatureIdentifier) {
        recordedTracks[creatureId] = track

        // Update the animation's tracks
        if let existingIndex = animation.tracks.firstIndex(where: { $0.creatureId == creatureId }) {
            animation.tracks[existingIndex] = track
        } else {
            animation.tracks.append(track)
        }
    }

    func removeTrack(for creatureId: CreatureIdentifier) {
        recordedTracks.removeValue(forKey: creatureId)
        animation.tracks.removeAll { $0.creatureId == creatureId }
    }

    func hasTrack(for creatureId: CreatureIdentifier) -> Bool {
        return recordedTracks[creatureId] != nil
    }
}

// MARK: - Recording Session View

struct AnimationRecordingSessionView: View {
    @ObservedObject var session: AnimationRecordingSession

    let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationRecordingSessionView")

    @State private var showingMetadataEditor = false
    @State private var selectedCreatureForRecording: Creature?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Animation metadata section
            AnimationMetadataCard(animation: session.animation) {
                showingMetadataEditor = true
            }

            // Recording section
            RecordingControlsView(session: session)

            // Tracks overview
            if !session.recordedTracks.isEmpty {
                TracksOverviewView(session: session)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingMetadataEditor) {
            AnimationMetadataEditorSheet(animation: session.animation)
        }
        .sheet(item: $selectedCreatureForRecording) { creature in
            NavigationView {
                RecordTrackForSession(creature: creature, session: session) {
                    selectedCreatureForRecording = nil
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            selectedCreatureForRecording = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct AnimationMetadataCard: View {
    let animation: Common.Animation
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Animation Details")
                    .font(.headline)
                Spacer()
                Button("Edit", action: onEdit)
                    .buttonStyle(.borderless)
            }

            if animation.metadata.title.isEmpty {
                Text("Untitled Animation")
                    .foregroundColor(.secondary)
            } else {
                Text(animation.metadata.title)
                    .font(.title2)
            }

            if !animation.metadata.soundFile.isEmpty {
                Label(animation.metadata.soundFile, systemImage: "speaker.wave.2")
                    .font(.caption)
            }

            if !animation.metadata.note.isEmpty {
                Text(animation.metadata.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct RecordingControlsView: View {
    @ObservedObject var session: AnimationRecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Tracks")
                .font(.headline)

            Text("Select creatures to record movement tracks for this animation:")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 200))
                ], spacing: 12
            ) {
                ForEach(session.availableCreatures) { creature in
                    CreatureRecordingCard(
                        creature: creature,
                        hasTrack: session.hasTrack(for: creature.id),
                        onRecord: {
                            selectedCreatureForRecording = creature
                        },
                        onRemove: {
                            session.removeTrack(for: creature.id)
                        }
                    )
                }
            }
        }
    }
}

struct CreatureRecordingCard: View {
    let creature: Creature
    let hasTrack: Bool
    let onRecord: () -> Void
    let onRemove: () -> Void

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

            HStack {
                if hasTrack {
                    Button("Re-record") {
                        onRecord()
                    }
                    .buttonStyle(.bordered)

                    Button("Remove") {
                        onRemove()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                } else {
                    Button("Record Track") {
                        onRecord()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasTrack ? Color.green : Color(.systemGray4), lineWidth: hasTrack ? 2 : 1)
        )
        .cornerRadius(8)
    }
}

struct TracksOverviewView: View {
    @ObservedObject var session: AnimationRecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded Tracks (\(session.recordedTracks.count))")
                .font(.headline)

            ForEach(Array(session.recordedTracks.keys), id: \.self) { creatureId in
                if let track = session.recordedTracks[creatureId],
                    let creature = session.availableCreatures.first(where: { $0.id == creatureId })
                {

                    HStack {
                        VStack(alignment: .leading) {
                            Text(creature.name)
                                .font(.headline)
                            Text("\(track.frames.count) frames recorded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Mini waveform preview would go here
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 60, height: 20)
                            .cornerRadius(4)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
}

struct AnimationMetadataEditorSheet: View {
    let animation: Common.Animation
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section("Basic Information") {
                    TextField("Animation Title", text: binding(for: \.metadata.title))
                    TextField("Sound File", text: binding(for: \.metadata.soundFile))
                    TextField("Notes", text: binding(for: \.metadata.note), axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Timing") {
                    TextField(
                        "Milliseconds per Frame",
                        value: binding(for: \.metadata.millisecondsPerFrame),
                        format: .number)
                    Toggle("Multi-track Audio", isOn: binding(for: \.metadata.multitrackAudio))
                }
            }
            .navigationTitle("Animation Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func binding<T>(for keyPath: ReferenceWritableKeyPath<Common.Animation, T>) -> Binding<
        T
    > {
        Binding(
            get: { animation[keyPath: keyPath] },
            set: { animation[keyPath: keyPath] = $0 }
        )
    }
}

#Preview {
    AnimationRecordingCoordinator()
}

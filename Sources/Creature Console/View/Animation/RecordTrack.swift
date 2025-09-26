import AVFoundation
import Common
import OSLog
import SwiftUI

struct RecordTrack: View {

    @Environment(\.presentationMode) var presentationMode

    @State private var appState = AppStateData(
        currentActivity: .idle, currentAnimation: nil, selectedTrack: nil, showSystemAlert: false,
        systemAlertMessage: "")
    let audioManager = AudioManager.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared

    let creatureManager = CreatureManager.shared
    @State private var joystickState = JoystickManagerState(
        aButtonPressed: false, bButtonPressed: false, xButtonPressed: false, yButtonPressed: false,
        selectedJoystick: .none)
    @State private var bButtonSymbol: String = "b.circle"

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("eventLoopMillisecondsPerFrame") var millisecondsPerFrame = 20

    @State private var errorMessage = ""
    @State private var showErrorMessage = false

    @State private var currentTrack: Track?

    @State private var isRecordingLocal = false
    @State private var isTransitioning = false
    @State private var previousBPressed = false

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RecordTrack")

    let creature: Creature
    let localAnimation: Common.Animation?

    let onTrackSaved: ((Track) -> Void)?

    init(creature: Creature, localAnimation: Common.Animation? = nil, onTrackSaved: ((Track) -> Void)? = nil) {
        self.creature = creature
        self.localAnimation = localAnimation
        self.onTrackSaved = onTrackSaved
    }

    @State var lastUpdated: Date = Date()

    var creaturePicked: Bool {
        true  // Always true since creature is required
    }

    // Use only localAnimation, do not fall back to appState.currentAnimation
    private var currentAnimation: Common.Animation? {
        return localAnimation
    }

    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var recordingTask: Task<Void, Never>? = nil

    var body: some View {
        GlassEffectContainer(spacing: 28) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("Press")
                    Image(systemName: bButtonSymbol)
                    Text(isRecordingLocal ? "to stop" : "to start")
                }
                .font(.title)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
                .frame(maxWidth: .infinity, alignment: .center)

                if isRecordingLocal {
                    JoystickDebugView()
                } else {
                    if let track = currentTrack {
                        VStack(spacing: 16) {
                            TrackViewer(track: track, creature: creature, inputs: creature.inputs)
                                .padding(.horizontal)

                            SoundDataImport(
                                track: Binding(
                                    get: {
                                        currentTrack!
                                    },
                                    set: { newTrack in
                                        currentTrack = newTrack
                                    }
                                ),
                                millisecondsPerFrame: currentAnimation?.metadata.millisecondsPerFrame ?? 20
                            )
                            .frame(maxWidth: .infinity)

                            HStack {
                                Button(action: {
                                    closeWithoutSaving()
                                }) {
                                    Label("Close Without Saving", systemImage: "nosign")
                                }
                                .buttonStyle(.glass)

                                Spacer()

                                Button(action: {
                                    Task { await saveAndGoHome() }
                                }) {
                                    Label("Save Track", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.glassProminent)
                            }
                            .padding(12)
                            .frame(maxWidth: 640)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Record Track")
        #if os(macOS)
            .navigationSubtitle(
                "Name: \(creature.name), Channel Offset: \(creature.channelOffset), Active Universe: \(activeUniverse)"
            )
        #endif
        .onDisappear {

            // Clean up our tasks if they're still running
            streamingTask?.cancel()
            recordingTask?.cancel()

        }
        .alert(isPresented: $showErrorMessage) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("WTF?"))
            )
        }
        .task {
            // Load initial states
            let initialAppState = AppStateData(
                currentActivity: await AppState.shared.getCurrentActivity,
                currentAnimation: await AppState.shared.getCurrentAnimation,
                selectedTrack: await AppState.shared.getSelectedTrack,
                showSystemAlert: await AppState.shared.getShowSystemAlert,
                systemAlertMessage: await AppState.shared.getSystemAlertMessage
            )
            await MainActor.run {
                appState = initialAppState
            }

            let initialButtonSymbol = await JoystickManager.shared.getBButtonSymbol()
            await MainActor.run {
                bButtonSymbol = initialButtonSymbol
            }

            logger.info(
                "RecordTrack: Initial state loaded - activity: \(initialAppState.currentActivity.description)"
            )
            if let animation = localAnimation {
                logger.info("RecordTrack: Current animation: \(animation.metadata.title)")
            }

            for await state in await AppState.shared.stateUpdates {
                await MainActor.run {
                    appState = state
                }
            }
        }
        .task {
            for await state in await JoystickManager.shared.stateUpdates {
                await MainActor.run {
                    joystickState = state
                }

                // Update button symbol when joystick state changes
                let buttonSymbol = await JoystickManager.shared.getBButtonSymbol()
                await MainActor.run {
                    bButtonSymbol = buttonSymbol
                }

                // Rising-edge detection for B button (no gate)
                let newB = state.bButtonPressed
                let wasB = previousBPressed
                previousBPressed = newB
                if newB && !wasB {
                    await MainActor.run {
                        if isRecordingLocal {
                            // Do not toggle isRecordingLocal here; stopRecording will set it when done.
                            stopRecording()
                        } else {
                            startRecording()
                            isRecordingLocal = true
                        }
                    }
                }
            }
        }

    }

    func playWarningTone() {

        logger.info("attempting to play the warning tone")

        let result = audioManager.playBundledSound(
            name: "recordingCountdownSound", extension: "flac")

        switch result {
        case .success(let data):
            logger.info("Warning tone playback result: \(data.description)")
        case .failure(let data):
            logger.warning("Warning tone playback failed: \(data.localizedDescription)")
        }

    }

    func startRecording() {

        logger.info("startRecording() called")
        // Stream to the creature for recording
        logger.info("Starting recording for creature: \(creature.name)")
        Task { await AppState.shared.setCurrentActivity(.preparingToRecord) }
        // Start streaming to the creature
        streamingTask = Task {

            let result = await creatureManager.startStreamingToCreature(creatureId: creature.id)
            switch result {
            case .success(let message):
                logger.debug("was able to start streaming: \(message)")
            case .failure(let error):
                logger.warning(
                    "unable to stream during a recording: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showErrorMessage = true
            }
        }

        // Work in the background
        recordingTask = Task {
            logger.info("recordingTask started (local state)")

            guard let animation = currentAnimation else {
                logger.warning("No current animation found - cannot record")
                return
            }

            self.currentTrack = Track(
                id: UUID(), creatureId: creature.id, animationId: animation.id, frames: [])

            do {
                logger.info("Playing warning tone...")
                await MainActor.run { playWarningTone() }
                logger.info("Sleeping for 3.8 seconds...")
                try await Task.sleep(nanoseconds: UInt64(3.8 * 1_000_000_000))
                logger.info("Sleep completed")
            } catch {
                logger.error("couldn't sleep: \(error)")
            }

            logger.info("calling creatureManager.startRecording(soundFile:)")
            await creatureManager.startRecording(soundFile: animation.metadata.soundFile)
            logger.info("creatureManager.startRecording() completed")
            await AppState.shared.setCurrentActivity(.recording)
        }

    }

    func stopRecording() {
        Task {
            await creatureManager.stopRecording()
            recordingTask?.cancel()
            logger.info("asked recording to stop")

            // Stop streaming
            let streamResult = await creatureManager.stopStreaming()
            switch streamResult {
            case .success(let message):
                logger.debug("streaming stopped: \(message)")
            case .failure(let error):
                logger.warning(
                    "unable to stop streaming while recording: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showErrorMessage = true
            }
            streamingTask?.cancel()

            // If everything went well, we have a track!
            if let animation = currentAnimation {
                let motionBuffer = await creatureManager.drainMotionBuffer()
                await MainActor.run {
                    currentTrack = Track(
                        id: UUID(),
                        creatureId: creature.id,
                        animationId: animation.id,
                        frames: motionBuffer)
                }
                
                await MainActor.run {
                    isRecordingLocal = false
                }
                await AppState.shared.setCurrentActivity(.idle)
            }
        }
    }

    func saveAndGoHome() async {

        logger.info("saving and going home")

        // Produce the track and hand it back to the caller
        if let track = currentTrack {
            // Prefer handing the track back to the parent, which can append and refresh UI
            onTrackSaved?(track)
            logger.debug("handed track back to parent via callback")
        } else {
            logger.warning("can't save because currentTrack is nil")
        }

        // Now go back
        presentationMode.wrappedValue.dismiss()
    }

    func closeWithoutSaving() {
        logger.info("closing the RecordTrack view without saving")
        presentationMode.wrappedValue.dismiss()
    }

}


struct RecordTrack_Previews: PreviewProvider {
    static var previews: some View {
        RecordTrack(creature: .mock())
    }
}


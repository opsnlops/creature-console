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

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RecordTrack")


    let creature: Creature
    let localAnimation: Common.Animation?

    init(creature: Creature, localAnimation: Common.Animation? = nil) {
        self.creature = creature
        self.localAnimation = localAnimation
    }

    @State var lastUpdated: Date = Date()

    var creaturePicked: Bool {
        true  // Always true since creature is required
    }

    // Use local animation if provided, otherwise fall back to AppState
    private var currentAnimation: Common.Animation? {
        return localAnimation ?? appState.currentAnimation
    }

    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var recordingTask: Task<Void, Never>? = nil

    var body: some View {
        VStack {


            HStack {
                Text("Press")
                    .font(.title)
                Image(systemName: bButtonSymbol)
                    .font(.title)
                if appState.currentActivity == .recording {
                    Text("to stop")
                        .font(.title)
                } else {
                    Text("to start")
                        .font(.title)
                }
            }

            // Show either nothing, the joystick debugger, or a waveform if we have one
            if appState.currentActivity == .preparingToRecord
                || appState.currentActivity == .recording
            {
                JoystickDebugView()
            } else {
                if let track = currentTrack {
                    VStack {
                        TrackViewer(track: track, creature: creature, inputs: creature.inputs)
                            .padding()

                        HStack {

                            Button(action: {
                                closeWithoutSaving()
                            }) {
                                Label("Close Without Saving", systemImage: "nosign")
                            }
                            .padding()

                            Button(action: {
                                saveAndGoHome()
                            }) {
                                Label("Save Track", systemImage: "square.and.arrow.down")
                                    .foregroundColor(.accentColor)
                            }
                            .padding()
                        }

                        // Unwrap the currentTrack and pass it as a Binding
                        SoundDataImport(
                            track: Binding(
                                get: {
                                    currentTrack!
                                },
                                set: { newTrack in
                                    currentTrack = newTrack
                                }))
                    }

                } else {
                    // If I replace this with an EmptyView() the form at the top gets centered and
                    // I just don't like how it looks
                    Spacer()
                }
            }


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
        .onChange(of: joystickState.bButtonPressed) {
            logger.info("B button state changed: \(joystickState.bButtonPressed)")
            if joystickState.bButtonPressed {
                Task {
                    let currentActivity = await AppState.shared.getCurrentActivity
                    logger.info(
                        "B button pressed! Current activity from AppState: \(currentActivity.description)"
                    )
                    switch currentActivity {
                    case .idle:
                        await MainActor.run {
                            startRecording()
                        }
                    case .recording:
                        await MainActor.run {
                            stopRecording()
                        }
                    case .preparingToRecord:
                        logger.debug("preparing to record - ignoring button press")
                    default:
                        logger.info(
                            "Setting activity to idle from state: \(currentActivity.description)"
                        )
                        await AppState.shared.setCurrentActivity(.idle)
                    }
                }
            }
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
            if let animation = initialAppState.currentAnimation {
                logger.info("RecordTrack: Current animation: \(animation.metadata.title)")
            } else {
                logger.warning("RecordTrack: No current animation set!")
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

            logger.info("recordingTask started - setting state to preparingToRecord")
            await AppState.shared.setCurrentActivity(.preparingToRecord)

            if let animation = currentAnimation {
                logger.info("Found current animation: \(animation.metadata.title)")
                self.currentTrack = Track(
                    id: UUID(), creatureId: creature.id, animationId: animation.id, frames: [])

                do {
                    logger.info("Playing warning tone...")
                    await MainActor.run {
                        playWarningTone()
                    }
                    logger.info("Sleeping for 3.8 seconds...")
                    try await Task.sleep(nanoseconds: UInt64(3.8 * 1_000_000_000))
                    logger.info("Sleep completed")
                } catch {
                    logger.error("couldn't sleep: \(error)")
                }

                logger.info("setting state to recording")
                await AppState.shared.setCurrentActivity(.recording)
                logger.info("calling creatureManager.startRecording()")
                await creatureManager.startRecording()
                logger.info("creatureManager.startRecording() completed")
            } else {
                logger.warning("No current animation found - cannot record")
            }
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

            await AppState.shared.setCurrentActivity(.idle)

            // If everything went well, we have a track!
            if let animation = currentAnimation {
                let motionBuffer = await creatureManager.motionDataBuffer
                currentTrack = Track(
                    id: UUID(),
                    creatureId: creature.id,
                    animationId: animation.id,
                    frames: motionBuffer)
            }
        }
    }

    func saveAndGoHome() {

        logger.info("saving and going home")

        // Add our track to the main animation
        if let animation = currentAnimation {
            if let track = currentTrack {
                DispatchQueue.main.async {
                    animation.tracks.append(track)
                }
                logger.debug("added our track! count is now: \(animation.tracks.count)")
            } else {
                logger.warning("can't save because currentTank is nil")
            }
        } else {
            logger.warning("can't save because currentAnimation is nil")
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

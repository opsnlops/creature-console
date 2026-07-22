import AVFoundation
import Common
import OSLog
import SwiftUI

/// A specialized version of RecordTrack that integrates with AnimationRecordingSession
struct RecordTrackForSession: View {

    let creature: Creature
    let session: AnimationRecordingSession
    let onComplete: () -> Void

    @State private var appState = AppStateData(
        currentActivity: .idle, currentAnimation: nil, selectedTrack: nil,
        showSystemAlert: false, systemAlertMessage: ""
    )

    let audioManager = AudioManager.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    @State private var joystickState = JoystickManagerState(
        aButtonPressed: false, bButtonPressed: false, xButtonPressed: false,
        yButtonPressed: false, selectedJoystick: .none
    )
    @State private var bButtonSymbol: String = "b.circle"

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("eventLoopMillisecondsPerFrame") var millisecondsPerFrame = 20

    @State private var errorAlert: ErrorAlert?
    @State private var currentTrack: Track?
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var recordingTask: Task<Void, Never>? = nil
    @State private var preparingSound: String? = nil

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RecordTrackForSession")

    var body: some View {
        VStack {
            // Recording instructions
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
            .padding()

            // Show either recording interface or results
            if appState.currentActivity == .preparingToRecord
                || appState.currentActivity == .recording
            {
                VStack {
                    if appState.currentActivity == .preparingToRecord {
                        VStack {
                            Text("Get Ready!")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text("Recording will start in a moment...")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }

                    JoystickDebugView()
                }
            } else if let track = currentTrack {
                // Show results
                VStack(spacing: 20) {
                    Text("Recording Complete!")
                        .font(.title2)
                        .foregroundStyle(.green)

                    TrackViewer(track: track, creature: creature, inputs: creature.inputs)
                        .padding()

                    Text("\(track.frames.count) frames recorded")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        Button("Discard") {
                            discardRecording()
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(.red)

                        Button("Save Track") {
                            saveTrackToSession()
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .padding()
                }
            } else {
                // Idle state
                VStack {
                    Image(systemName: "record.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)

                    Text("Ready to Record")
                        .font(.title2)

                    Text("Recording track for \(creature.name)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            }

            Spacer()
        }
        .navigationTitle("Record \(creature.name)")
        .onDisappear {
            // Clean up tasks
            streamingTask?.cancel()
            recordingTask?.cancel()
        }
        .onChange(of: joystickState.bButtonPressed) {
            if joystickState.bButtonPressed {
                handleButtonPress()
            }
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
            appState = initialAppState

            bButtonSymbol = JoystickManager.shared.getBButtonSymbol()

            // Subscribe to state updates
            for await state in await AppState.shared.stateUpdates {
                appState = state
            }
        }
        .task {
            for await state in await JoystickManager.shared.stateUpdates {
                joystickState = state
                bButtonSymbol = JoystickManager.shared.getBButtonSymbol()
            }
        }
        .errorAlert($errorAlert)
        .overlay {
            if let name = preparingSound {
                ProcessingOverlayView(message: "Preparing \(name)…", progress: nil)
            }
        }
        .animation(.default, value: preparingSound != nil)
    }

    private func handleButtonPress() {
        logger.debug("B button pressed!")

        Task {
            let currentActivity = await AppState.shared.getCurrentActivity
            logger.debug("Current activity: \(currentActivity.description)")

            switch currentActivity {
            case .idle:
                startRecording()
            case .recording:
                stopRecording()
            case .preparingToRecord:
                logger.debug("Preparing to record - ignoring button press")
            default:
                logger.debug("Setting activity to idle from state: \(currentActivity.description)")
                await AppState.shared.setCurrentActivity(.idle)
            }
        }
    }

    private func startRecording() {
        logger.debug("Starting recording for creature: \(creature.name)")

        // Start streaming to the creature
        streamingTask = Task {
            let result = await creatureManager.startStreamingToCreature(creatureId: creature.id)
            switch result {
            case .success(let message):
                logger.debug("Started streaming: \(message)")
            case .failure(let error):
                logger.warning("Unable to start streaming: \(error.localizedDescription)")
                errorAlert = ErrorAlert(
                    title: "Recording Error", message: error.localizedDescription)
            }
        }

        // Recording workflow with synchronized audio/motion capture
        recordingTask = Task {
            logger.debug("Recording task started - setting state to preparingToRecord")
            await AppState.shared.setCurrentActivity(.preparingToRecord)

            // Create new track for this session
            self.currentTrack = Track(
                id: UUID(),
                creatureId: creature.id,
                animationId: session.animation.id,
                frames: []
            )

            // ═══════════════════════════════════════════════════════════════════════
            // PHASE 1: Prepare Sound File (can take several seconds for large WAVs)
            // ═══════════════════════════════════════════════════════════════════════
            // This downloads and processes the sound file BEFORE the countdown timer.
            // For 17-channel WAV files, this includes downmixing to mono which can be slow.
            // Shows glass-effect progress overlay during preparation.
            let soundFile = session.animation.metadata.soundFile
            if !soundFile.isEmpty {
                logger.debug("Preparing sound file: \(soundFile)")
                preparingSound = soundFile
                let prepResult = await creatureManager.prepareSoundForRecording(
                    soundFile: soundFile)
                preparingSound = nil
                switch prepResult {
                case .success:
                    logger.debug("Sound file prepared successfully")
                case .failure(let error):
                    logger.error("Failed to prepare sound: \(String(describing: error))")
                    errorAlert = ErrorAlert(
                        title: "Recording Error", message: error.localizedDescription)
                    await AppState.shared.setCurrentActivity(.idle)
                    return
                }
            }

            // ═══════════════════════════════════════════════════════════════════════
            // PHASE 2: Countdown Timer (3.5 seconds, synced with haptics at 2.0s, 2.5s, 3.0s, 3.5s)
            // ═══════════════════════════════════════════════════════════════════════
            // Gives user time to prepare. Sound file is already downloaded and armed.
            do {
                logger.debug("Playing warning tone...")
                playWarningTone()
                logger.debug("Sleeping for 3.5 seconds...")
                try await Task.sleep(nanoseconds: UInt64(3.5 * 1_000_000_000))
                logger.debug("Sleep completed")
            } catch {
                logger.error("Couldn't sleep: \(error)")
            }

            // ═══════════════════════════════════════════════════════════════════════
            // PHASE 3: Start Recording with Precise Audio Sync
            // ═══════════════════════════════════════════════════════════════════════
            // Uses mach_absolute_time() to schedule audio at precise time for perfect sync.
            // Motion capture and audio start simultaneously at the 3.5s mark.
            logger.debug("Setting state to recording")
            await AppState.shared.setCurrentActivity(.recording)
            logger.debug("Starting recording in CreatureManager")
            await creatureManager.startRecording(delaySoundStart: 0.0)
            logger.debug("CreatureManager recording started")
        }
    }

    private func stopRecording() {
        Task {
            await creatureManager.stopRecording()
            recordingTask?.cancel()
            logger.debug("Asked recording to stop")

            // Stop streaming
            let streamResult = await creatureManager.stopStreaming()
            switch streamResult {
            case .success(let message):
                logger.debug("Streaming stopped: \(message)")
            case .failure(let error):
                logger.warning("Unable to stop streaming: \(error.localizedDescription)")
                errorAlert = ErrorAlert(
                    title: "Recording Error", message: error.localizedDescription)
            }
            streamingTask?.cancel()

            await AppState.shared.setCurrentActivity(.idle)

            // Get recorded data
            let motionBuffer = await creatureManager.motionDataBuffer
            currentTrack = Track(
                id: UUID(),
                creatureId: creature.id,
                animationId: session.animation.id,
                frames: motionBuffer
            )
        }
    }

    private func playWarningTone() {
        logger.debug("Playing warning tone")

        let result = audioManager.playBundledSound(
            name: "recordingCountdownSound", extension: "flac")
        switch result {
        case .success(let data):
            logger.debug("Warning tone playback result: \(data.description)")
        case .failure(let data):
            logger.warning("Warning tone playback failed: \(data.localizedDescription)")
        }
    }

    private func saveTrackToSession() {
        guard let track = currentTrack else {
            logger.warning("No track to save")
            return
        }

        logger.debug("Saving track to session for creature: \(creature.name)")
        session.addTrack(track, for: creature.id)

        // Update the AppState animation
        Task {
            await AppState.shared.setCurrentAnimation(session.animation)
        }

        onComplete()
    }

    private func discardRecording() {
        logger.debug("Discarding recording")
        currentTrack = nil
        onComplete()
    }
}

#Preview {
    struct PreviewWrapper: View {
        let session = AnimationRecordingSession(
            animation: Common.Animation(),
            availableCreatures: [.mock()]
        )

        var body: some View {
            NavigationStack {
                RecordTrackForSession(
                    creature: .mock(),
                    session: session,
                    onComplete: {}
                )
            }
        }
    }

    return PreviewWrapper()
}

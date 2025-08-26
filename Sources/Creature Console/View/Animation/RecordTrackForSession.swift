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
    
    @State private var errorMessage = ""
    @State private var showErrorMessage = false
    @State private var currentTrack: Track?
    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var recordingTask: Task<Void, Never>? = nil
    
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
            if appState.currentActivity == .preparingToRecord || appState.currentActivity == .recording {
                VStack {
                    if appState.currentActivity == .preparingToRecord {
                        VStack {
                            Text("Get Ready!")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text("Recording will start in a moment...")
                                .font(.body)
                                .foregroundColor(.secondary)
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
                        .foregroundColor(.green)
                    
                    TrackViewer(track: track, creature: creature, inputs: creature.inputs)
                        .padding()
                    
                    Text("\\(track.frames.count) frames recorded")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        Button("Discard") {
                            discardRecording()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        
                        Button("Save Track") {
                            saveTrackToSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            } else {
                // Idle state
                VStack {
                    Image(systemName: "record.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Ready to Record")
                        .font(.title2)
                    
                    Text("Recording track for \\(creature.name)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(40)
            }
            
            Spacer()
        }
        .navigationTitle("Record \\(creature.name)")
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
            await MainActor.run {
                appState = initialAppState
            }
            
            let initialButtonSymbol = await JoystickManager.shared.getBButtonSymbol()
            await MainActor.run {
                bButtonSymbol = initialButtonSymbol
            }
            
            // Subscribe to state updates
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
                
                let buttonSymbol = await JoystickManager.shared.getBButtonSymbol()
                await MainActor.run {
                    bButtonSymbol = buttonSymbol
                }
            }
        }
        .alert(isPresented: $showErrorMessage) {
            Alert(
                title: Text("Recording Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func handleButtonPress() {
        logger.info("B button pressed!")
        
        Task {
            let currentActivity = await AppState.shared.getCurrentActivity
            logger.info("Current activity: \\(currentActivity.description)")
            
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
                logger.debug("Preparing to record - ignoring button press")
            default:
                logger.info("Setting activity to idle from state: \\(currentActivity.description)")
                await AppState.shared.setCurrentActivity(.idle)
            }
        }
    }
    
    private func startRecording() {
        logger.info("Starting recording for creature: \\(creature.name)")
        
        // Start streaming to the creature
        streamingTask = Task {
            let result = await creatureManager.startStreamingToCreature(creatureId: creature.id)
            switch result {
            case .success(let message):
                logger.debug("Started streaming: \\(message)")
            case .failure(let error):
                logger.warning("Unable to start streaming: \\(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorMessage = true
                }
            }
        }
        
        // Start recording workflow
        recordingTask = Task {
            logger.info("Recording task started - setting state to preparingToRecord")
            await AppState.shared.setCurrentActivity(.preparingToRecord)
            
            // Create new track for this session
            self.currentTrack = Track(
                id: UUID(), 
                creatureId: creature.id, 
                animationId: session.animation.id, 
                frames: []
            )
            
            do {
                logger.info("Playing warning tone...")
                await MainActor.run {
                    playWarningTone()
                }
                logger.info("Sleeping for 3.8 seconds...")
                try await Task.sleep(nanoseconds: UInt64(3.8 * 1_000_000_000))
                logger.info("Sleep completed")
            } catch {
                logger.error("Couldn't sleep: \\(error)")
            }
            
            logger.info("Setting state to recording")
            await AppState.shared.setCurrentActivity(.recording)
            logger.info("Starting recording in CreatureManager")
            await creatureManager.startRecording()
            logger.info("CreatureManager recording started")
        }
    }
    
    private func stopRecording() {
        Task {
            await creatureManager.stopRecording()
            recordingTask?.cancel()
            logger.info("Asked recording to stop")
            
            // Stop streaming
            let streamResult = await creatureManager.stopStreaming()
            switch streamResult {
            case .success(let message):
                logger.debug("Streaming stopped: \\(message)")
            case .failure(let error):
                logger.warning("Unable to stop streaming: \\(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorMessage = true
                }
            }
            streamingTask?.cancel()
            
            await AppState.shared.setCurrentActivity(.idle)
            
            // Get recorded data
            let motionBuffer = await creatureManager.motionDataBuffer
            await MainActor.run {
                currentTrack = Track(
                    id: UUID(),
                    creatureId: creature.id,
                    animationId: session.animation.id,
                    frames: motionBuffer
                )
            }
        }
    }
    
    private func playWarningTone() {
        logger.info("Playing warning tone")
        
        let result = audioManager.playBundledSound(name: "recordingCountdownSound", extension: "flac")
        switch result {
        case .success(let data):
            logger.info("Warning tone playback result: \\(data.description)")
        case .failure(let data):
            logger.warning("Warning tone playback failed: \\(data.localizedDescription)")
        }
    }
    
    private func saveTrackToSession() {
        guard let track = currentTrack else {
            logger.warning("No track to save")
            return
        }
        
        logger.info("Saving track to session for creature: \\(creature.name)")
        session.addTrack(track, for: creature.id)
        
        // Update the AppState animation
        Task {
            await AppState.shared.setCurrentAnimation(session.animation)
        }
        
        onComplete()
    }
    
    private func discardRecording() {
        logger.info("Discarding recording")
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
            NavigationView {
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
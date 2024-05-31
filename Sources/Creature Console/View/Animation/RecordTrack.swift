import AVFoundation
import Common
import OSLog
import SwiftUI

struct RecordTrack: View {

    @Environment(\.presentationMode) var presentationMode

    let appState = AppState.shared
    let audioManager = AudioManager.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared


    @ObservedObject var creatureManager = CreatureManager.shared
    @ObservedObject var joystickManager = JoystickManager.shared

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("eventLoopMillisecondsPerFrame") var millisecondsPerFrame = 20

    @State private var errorMessage = ""
    @State private var showErrorMessage = false

    @State private var currentTrack: Track?

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RecordTrack")


    @State private var showCreatureSheet: Bool = true
    @State var creature: Creature? {
        didSet {
            showCreatureSheet = creature == nil
        }
    }

    @State var lastUpdated: Date = Date()

    var creaturePicked: Bool {
        creature != nil
    }

    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var recordingTask: Task<Void, Never>? = nil

    var body: some View {
        if let c = creature {
            VStack {


                HStack {
                    Text("Press")
                        .font(.title)
                    Image(systemName: joystickManager.getActiveJoystick().getBButtonSymbol())
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
                            TrackViewer(track: track, creature: c, inputs: c.inputs)
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
                    "Name: \(c.name), Channel Offset: \(c.channelOffset), Active Universe: \(activeUniverse)"
                )
            #endif
            .onDisappear {

                // Clean up our tasks if they're still running
                streamingTask?.cancel()
                recordingTask?.cancel()

            }
            .onChange(of: joystickManager.bButtonPressed) {
                if joystickManager.bButtonPressed {
                    switch appState.currentActivity {
                    case .idle:
                        startRecording()
                    case .recording:
                        stopRecording()
                    case .preparingToRecord:
                        print("preparing to record")
                    default:
                        appState.currentActivity = .idle
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

        } else {
            Text("No creature is chosen to record with")
                .sheet(isPresented: $showCreatureSheet) {
                    ChooseCreatureSheet(selectedCreature: $creature)
                }
        }
    }

    func playWarningTone() {

        logger.info("attempting to play the warning tone")

        let result = audioManager.playBundledSound(
            name: "recordingCountdownSound", extension: "flac")

        switch result {
        case .success(let data):
            logger.info("\(data.description)")
        case .failure(let data):
            logger.warning("\(data.localizedDescription)")
        }

    }

    func startRecording() {

        // It doesn't make sense to do this if we don't have a creature picked
        if let c = creature {

            // Start streaming to the creature
            streamingTask = Task {

                switch creatureManager.startStreamingToCreature(creatureId: c.id) {
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

                appState.currentActivity = .preparingToRecord

                if let animation = appState.currentAnimation {
                    self.currentTrack = Track(
                        id: UUID(), creatureId: c.id, animationId: animation.id, frames: [])

                    do {
                        playWarningTone()
                        try await Task.sleep(nanoseconds: UInt64(3.8 * 1_000_000_000))
                    } catch {
                        logger.error("couldn't sleep?")
                    }

                    logger.info("setting state to recording")
                    appState.currentActivity = .recording
                    creatureManager.startRecording()
                }
            }
        } else {
            logger.warning("unable to record with an un-chosen creature")
        }

    }

    func stopRecording() {
        creatureManager.stopRecording()
        recordingTask?.cancel()
        logger.info("asked recording to stop")

        // Stop streaming
        switch creatureManager.stopStreaming() {
        case .success(let message):
            logger.debug("streaming stopped: \(message)")
        case .failure(let error):
            logger.warning(
                "unable to stop streaming while recording: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
        streamingTask?.cancel()


        appState.currentActivity = .idle

        // If everything went well, we have a track!
        if let creature = creature {
            if let animation = appState.currentAnimation {
                currentTrack = Track(
                    id: UUID(),
                    creatureId: creature.id,
                    animationId: animation.id,
                    frames: creatureManager.motionDataBuffer)
            }
        }
    }

    func saveAndGoHome() {

        logger.info("saving and going home")

        // Add our track to the main animation
        if let currentAnimation = appState.currentAnimation {
            if let track = currentTrack {
                DispatchQueue.main.async {
                    currentAnimation.tracks.append(track)
                }
                logger.debug("added our track! count is now: \(currentAnimation.tracks.count)")
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

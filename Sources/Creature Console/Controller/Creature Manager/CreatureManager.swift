
import Combine
import Foundation
import OSLog
import SwiftUI
import Common



/**
 The `CreatureManager` is what owns talking to all of the creatures. This allows me to keep SwiftUI things out of the [CreatureServerClient]
 */
class CreatureManager: ObservableObject {

    internal var server = CreatureServerClient.shared
    private var joystickManager = JoystickManager.shared
    private var audioManager = AudioManager.shared
    internal var creatureCache = CreatureCache.shared

    // Allllll by my seeelllllffffff
    static let shared = CreatureManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureManager")

    @ObservedObject var appState = AppState.shared
    
    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("audioFilePath") var audioFilePath: String = ""

    private var streamingCreature: CreatureIdentifier?
    private var isStreaming: Bool = false
    private var isRecording: Bool = false

    // Create a buffer to use for recording
    public private(set) var motionDataBuffer: [Data] = []

    private init() {
    }

    func startStreamingToCreature(creatureId: CreatureIdentifier) -> Result<String, ServerError> {

        guard !isStreaming else {
            return .failure(.communicationError("We're already streaming!"))
        }

        self.streamingCreature = creatureId
        self.isStreaming = true

        return .success("Started streaming to \(creatureId)")
    }


    func stopStreaming() -> Result<String, ServerError> {
        
        guard isStreaming else {
            return .failure(.communicationError("Streaming not happening"))
        }

        self.isStreaming = false
        self.streamingCreature = nil

        return .success("Stopped streaming")

    }

    /**
     This is called from the event look when it's our time to grab a frame
     */
    func onEventLoopTick() {

        if isStreaming {

            if let creatureId = streamingCreature  {

                let motionData = Data(joystickManager.values).base64EncodedString()
                let streamFrameData = StreamFrameData(ceatureId: creatureId, universe: activeUniverse, data: motionData)

                Task {
                    await server.streamFrame(streamFrameData: streamFrameData)
                }
            }
        }

        if isRecording {

            // Add the current value of the joystick to the buffer
            motionDataBuffer.append(Data(joystickManager.values))

        }

    }


    /**
     Called automatically when our state changes to recording
     */
    func startRecording() {

        logger.info("CreatureManager told it's time to start recording!")

        // Do we have a sound file to play?
        var soundFile: String = ""
        if let animation = appState.currentAnimation {

            soundFile = animation.metadata.soundFile
            logger.debug("Using sound file \(soundFile)")
        }

        // Set our state to recording
        DispatchQueue.main.async {
            self.appState.currentActivity = .recording
        }

        // Blank out the buffer
        motionDataBuffer = []

        // If it has a sound file attached, let's play it
        if !soundFile.isEmpty {

            // See if it's a valid url
            if let url = URL(string: audioFilePath + soundFile) {

                do {
                    logger.info("audiofile URL is \(url)")
                    Task {
                        await audioManager.play(url: url)
                    }
                }
            } else {
                logger.warning(
                    "audioFile URL doesn't exist: \(self.audioFilePath + soundFile)")
            }
        } else {
            logger.info("no audio file, skipping playback")
        }

        // Tell the system to start recording
        isRecording = true
    }

    /**
     Called automatically when our state changes to idle
     */
    func stopRecording() {
        isRecording = false
        logger.info("Stopped recording")
    }


    /**
     Play an animation on the server

     This tells the server which animation to play, and on what universe.
     */
    func playStoredAnimationOnServer(animationId: AnimationIdentifier, universe: UniverseIdentifier) async -> Result<String, ServerError> {
        logger.debug("asking the server to play animation \(animationId) on universe \(universe)")

        guard !animationId.isEmpty else {
            let errorMessage = "Unable to play an animation with an empty animationId"
            logger.warning("Can't play animation: \(errorMessage)")
            return .failure(.dataFormatError(errorMessage))
        }

        let result = await server.playStoredAnimation(animationId: animationId, universe: universe)
        switch(result) {
        case .success(let message):
            logger.info("Animation scheduled: \(message)")
            return .success(message)
        case .failure(let error):
            logger.warning("Unable to schedule animation: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /**
     Play an animation locally

     This requires a full [Animation] object, because we might not have saved it to the server. The idea is to be able
     to play it before we save it.
     */
    func playAnimationLocally(animation: Common.Animation, universe: UniverseIdentifier) async -> Result<String, ServerError> {
        return .failure(.notImplemented("This hasn't been implemented yet"))
    }
}

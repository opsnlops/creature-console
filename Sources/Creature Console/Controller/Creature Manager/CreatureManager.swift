import Common
import Foundation
import OSLog
import SwiftUI

/// The `CreatureManager` is what owns talking to all of the creatures. This allows me to keep SwiftUI things out of the [CreatureServerClient]
actor CreatureManager {

    internal var server = CreatureServerClient.shared

    // Allllll by my seeelllllffffff
    static let shared = CreatureManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureManager")

    private var activeUniverse: UniverseIdentifier {
        UniverseIdentifier(UserDefaults.standard.integer(forKey: "activeUniverse"))
    }

    private var streamingCreature: CreatureIdentifier?
    private var isRecording: Bool = false

    // Create a buffer to use for recording
    public private(set) var motionDataBuffer: [Data] = []

    private init() {
    }

    func startStreamingToCreature(creatureId: CreatureIdentifier) async -> Result<String, ServerError> {

        logger.info("startStreamingToCreature called - creatureId: \(creatureId)")
        
        self.streamingCreature = creatureId
        
        logger.info("Streaming started successfully")

        return .success("Started streaming to \(creatureId)")
    }


    func stopStreaming() async -> Result<String, ServerError> {

        logger.info("stopStreaming called")
        
        self.streamingCreature = nil
        
        logger.info("Streaming stopped successfully")

        return .success("Stopped streaming")

    }

    /// This is called from the event look when it's our time to grab a frame
    func onEventLoopTick() async {

        let currentActivity = await AppState.shared.getCurrentActivity
        if currentActivity == .streaming {

            if let creatureId = streamingCreature {

                let joystickValues = await JoystickManager.shared.getValues()
                let motionData = Data(joystickValues).base64EncodedString()
                let streamFrameData = StreamFrameData(
                    ceatureId: creatureId, universe: activeUniverse, data: motionData)

                await server.streamFrame(streamFrameData: streamFrameData)
            }
        }

        if isRecording {

            // Add the current value of the joystick to the buffer
            let joystickValues = await JoystickManager.shared.getValues()
            motionDataBuffer.append(Data(joystickValues))

        }

    }


    /// Called automatically when our state changes to recording
    func startRecording() async {

        logger.info("CreatureManager told it's time to start recording!")

        // Do we have a sound file to play?
        var soundFile: String = ""
        let animation = await AppState.shared.getCurrentAnimation
        if let animation = animation {
            soundFile = animation.metadata.soundFile
            logger.debug("Using sound file \(soundFile)")
        }

        // Set our state to recording
        await AppState.shared.setCurrentActivity(.recording)

        // Blank out the buffer
        motionDataBuffer = []

        // If it has a sound file attached, let's play it
        if !soundFile.isEmpty {

            // See if it's a valid url
            let urlRequest = server.getSoundURL(soundFile)
            switch urlRequest {
            case .success(let url):
                logger.info("audiofile URL is \(url)")
                Task { @MainActor in
                    _ = AudioManager.shared.playURL(url)
                }
            case .failure(_):
                logger.warning(
                    "audioFile URL doesn't exist: \(soundFile)")
            }


        } else {
            logger.info("no audio file, skipping playback")
        }

        // Tell the system to start recording
        isRecording = true
    }

    /// Called automatically when our state changes to idle
    func stopRecording() {
        isRecording = false
        logger.info("Stopped recording")
    }


    /// Play an animation on the server
    ///
    /// This tells the server which animation to play, and on what universe.
    func playStoredAnimationOnServer(animationId: AnimationIdentifier, universe: UniverseIdentifier)
        async -> Result<String, ServerError>
    {
        logger.debug("asking the server to play animation \(animationId) on universe \(universe)")

        guard !animationId.isEmpty else {
            let errorMessage = "Unable to play an animation with an empty animationId"
            logger.warning("Can't play animation: \(errorMessage)")
            return .failure(.dataFormatError(errorMessage))
        }

        let result = await server.playStoredAnimation(animationId: animationId, universe: universe)
        switch result {
        case .success(let message):
            logger.info("Animation scheduled: \(message)")
            return .success(message)
        case .failure(let error):
            logger.warning("Unable to schedule animation: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Play an animation locally
    ///
    /// This requires a full [Animation] object, because we might not have saved it to the server. The idea is to be able
    /// to play it before we save it.
    func playAnimationLocally(animation: Common.Animation, universe: UniverseIdentifier) async
        -> Result<String, ServerError>
    {
        return .failure(.notImplemented("This hasn't been implemented yet"))
    }
}

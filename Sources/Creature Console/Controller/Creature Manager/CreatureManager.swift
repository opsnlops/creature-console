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

    func startStreamingToCreature(creatureId: CreatureIdentifier) async -> Result<
        String, ServerError
    > {

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

        if let creatureId = streamingCreature {
            let joystickValues = await JoystickManager.shared.getValues()
            let motionData = Data(joystickValues).base64EncodedString()
            let streamFrameData = StreamFrameData(
                ceatureId: creatureId, universe: activeUniverse, data: motionData)
            let streamResult = await server.streamFrame(streamFrameData: streamFrameData)
            switch streamResult {
            case .success:
                break
            case .failure(let error):
                logger.warning("Failed to stream frame: \(error.localizedDescription)")
            }
        }

        if isRecording {

            // Add the current value of the joystick to the buffer
            let joystickValues = await JoystickManager.shared.getValues()
            motionDataBuffer.append(Data(joystickValues))

        }

    }


    /// Prepare the sound file for recording (download and arm for precise playback).
    ///
    /// **Two-Phase Recording Process:**
    /// This is phase 1 of 2 for synchronized recording. Call this method BEFORE the countdown
    /// timer begins to allow time for downloading and processing large sound files.
    ///
    /// **Workflow:**
    /// 1. Call `prepareSoundForRecording()` ← Downloads & processes audio (can be slow)
    /// 2. Play countdown warning tone (3.3-3.6 seconds)
    /// 3. Call `startRecording()` ← Starts audio at precise time + begins motion capture
    ///
    /// This separation ensures the 3.5-second countdown is consistent regardless of
    /// sound file size, and prevents audio/motion desynchronization.
    ///
    /// - Parameter soundFile: The sound file name from animation metadata (e.g., "music.wav")
    /// - Returns: `.success(())` if prepared, `.failure(AudioError)` with UI-displayable error
    func prepareSoundForRecording(soundFile: String) async -> Result<Void, AudioError> {
        guard !soundFile.isEmpty else {
            logger.info("no audio file, skipping preparation")
            return .success(())
        }

        logger.info("Preparing sound file for recording: \(soundFile)")
        let result = await AudioManager.shared.prepareAndArmSoundFile(fileName: soundFile)
        switch result {
        case .success:
            logger.info("Sound file prepared and armed successfully")
            return .success(())
        case .failure(let error):
            logger.error("Failed to prepare sound file: \(String(describing: error))")
            return .failure(error)
        }
    }

    /// Start recording and play the armed sound file at a precise time.
    ///
    /// **Two-Phase Recording Process:**
    /// This is phase 2 of 2 for synchronized recording. Must call `prepareSoundForRecording()`
    /// first, then wait for countdown, then call this method.
    ///
    /// **Precise Timing:**
    /// Uses `mach_absolute_time()` via `AudioManager.startArmedPreview()` to schedule
    /// audio playback at a sample-accurate time in the near future. This ensures:
    /// - Audio starts exactly when motion recording begins
    /// - No race conditions between audio and motion data
    /// - Consistent synchronization across all recording sessions
    ///
    /// **Timing Breakdown:**
    /// - `delaySoundStart: 0.2` = Schedule audio 200ms in future
    /// - `isRecording = true` = Begin motion capture immediately
    /// - Audio engine plays at precise host time (200ms later)
    ///
    /// - Parameter delaySoundStart: Delay in seconds before starting armed audio (default: 0.0)
    ///                              Recommended: 0.1-0.2s for best synchronization
    func startRecording(delaySoundStart: TimeInterval = 0.0) async {
        logger.info("CreatureManager told it's time to start recording!")

        // Reset recording state and buffer
        isRecording = false
        motionDataBuffer = []

        // Start the armed sound (if any) at a precise time using mach_absolute_time()
        await MainActor.run {
            let result = AudioManager.shared.startArmedPreview(in: delaySoundStart)
            switch result {
            case .success(let hostTime):
                logger.info("Started armed sound at host time: \(hostTime)")
            case .failure(let error):
                logger.debug(
                    "No armed sound to play (this is OK if no sound file): \(String(describing: error))"
                )
            }
        }

        // Begin recording motion data immediately
        isRecording = true
    }

    /// Called automatically when our state changes to idle
    func stopRecording() {
        isRecording = false
        logger.info("Stopped recording")
    }

    func drainMotionBuffer() -> [Data] {
        let buffer = motionDataBuffer
        motionDataBuffer = []
        return buffer
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

    /// Interrupt current playback with an animation on the server
    ///
    /// This tells the server to interrupt any currently playing playlist, play the specified
    /// animation, and then resume the playlist if resumePlaylist is true.
    func interruptWithAnimation(
        animationId: AnimationIdentifier, universe: UniverseIdentifier, resumePlaylist: Bool = true
    ) async -> Result<String, ServerError> {
        logger.debug(
            "asking the server to interrupt with animation \(animationId) on universe \(universe), resumePlaylist: \(resumePlaylist)"
        )

        guard !animationId.isEmpty else {
            let errorMessage = "Unable to interrupt with an animation with an empty animationId"
            logger.warning("Can't interrupt animation: \(errorMessage)")
            return .failure(.dataFormatError(errorMessage))
        }

        let result = await server.interruptWithAnimation(
            animationId: animationId, universe: universe, resumePlaylist: resumePlaylist)
        switch result {
        case .success(let message):
            logger.info("Animation interrupt scheduled: \(message)")
            return .success(message)
        case .failure(let error):
            logger.warning("Unable to schedule animation interrupt: \(error.localizedDescription)")
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

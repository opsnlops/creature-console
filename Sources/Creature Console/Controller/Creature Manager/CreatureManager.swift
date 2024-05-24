
import Combine
import Foundation
import OSLog
import SwiftUI
import Common



/**
 The `CreatureManager` is what owns talking to all of the creatures. This allows me to keep SwiftUI things out of the [CreatureServerClient]
 */
class CreatureManager: ObservableObject {

    var server = CreatureServerClient.shared
    var joystickManager = JoystickManager.shared
    var audioManager = AudioManager.shared
    var creatureCache = CreatureCache.shared

    // Allllll by my seeelllllffffff
    static let shared = CreatureManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureManager")

    @ObservedObject var appState = AppState.shared
    
    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("audioFilePath") var audioFilePath: String = ""

    private var streamingCreature: CreatureIdentifier?
    private var isStreaming: Bool = false


    // If we've got an animation loaded, keep track of it
    var animation: Common.Animation?
    var isRecording = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        appState.$currentActivity
            .sink { activity in
                if activity == .recording {
                    self.startRecording()
                } else if activity == .idle {
                    self.stopRecording()
                }
            }
            .store(in: &cancellables)
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

    }



    func recordNewAnimation(metadata: AnimationMetadata) {
        animation = Animation(
            id: DataHelper.generateRandomId(),
            metadata: metadata,
            tracks: [])

        // Set our state to recording
        DispatchQueue.main.async {
            self.appState.currentActivity = .recording
        }

        // If it has a sound file attached, let's play it
        if !metadata.soundFile.isEmpty {

            // See if it's a valid url
            if let url = URL(string: audioFilePath + metadata.soundFile) {

                do {
                    logger.info("audiofile URL is \(url)")
                    Task {
                        await audioManager.play(url: url)
                    }
                }
            } else {
                logger.warning(
                    "audioFile URL doesn't exist: \(self.audioFilePath + metadata.soundFile)")
            }
        } else {
            logger.info("no audio file, skipping playback")
        }

        // Tell the system to start recording
        isRecording = true
    }

    private func startRecording() {
//           AppState.shared.currentAnimation = Animation()
//           AppState.shared.currentAnimation?.isRecording = true
       }

       private func stopRecording() {
           //AppState.shared.currentAnimation?.isRecording = false
       }


    /**
     Play an animation on the server

     This tells the server which animation to play, and on what universe.
     */
    func playAnimationOnServer(animationId: AnimationIdentifier, universe: UniverseIdentifier) -> Result<String, ServerError> {
        return .failure(.notImplemented("this isn't implemented yet"))

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

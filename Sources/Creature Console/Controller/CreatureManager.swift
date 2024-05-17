

import Foundation
import OSLog
import SwiftUI
import Common



/**
 The `CreatureManager` is what owns talking to all of the creatures. This allows me to keep SwiftUI things out of the [CreatureServerClient]
 */
class CreatureManager {

    private var server = CreatureServerClient.shared
    private var joystickManager = JoystickManager.shared

    // Allllll by my seeelllllffffff
    static let shared = CreatureManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureManager")

    @ObservedObject var appState = AppState.shared
    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1





    private var streamingCreature: CreatureIdentifier?
    private var isStreaming: Bool = false


    private init() {}

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

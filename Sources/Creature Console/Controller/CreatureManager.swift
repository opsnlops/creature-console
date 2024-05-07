

import Foundation
import OSLog
import SwiftUI



/**
 The `CreatureManager` is what owns talking to all of the creatures. This allows me to keep SwiftUI things out of the [CreatureServerClient]
 */
class CreatureManager {

    // Allllll by my seeelllllffffff
    static let shared = CreatureManager()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureManager")

    @ObservedObject var appState = AppState.shared
    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1


    private init() {}


    func startStreamingToCreature(creatureId: CreatureIdentifier) -> Result<String, ServerError> {
        return .failure(.notImplemented("This hasn't been implemented yet"))
    }


    func stopStreaming() -> Result<String, ServerError> {
        return .failure(.notImplemented("This isn't implemented yet"))
    }

    /**
     This is called from the event look when it's our time to grab a frame
     */
    func grabFrame() async {

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
    func playAnimationLocally(animation: Animation, universe: UniverseIdentifier) async -> Result<String, ServerError> {
        return .failure(.notImplemented("This hasn't been implemented yet"))
    }
}


import Foundation
import OSLog


extension CreatureServerClient {


    func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }
    
    func listAnimations(creatureId: CreatureIdentifier) async -> Result<[AnimationMetadata], ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    func getAnimation(animationId: AnimationIdentifier) async -> Result<Animation, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    func updateAnimation(animation: Animation) async -> Result<String, ServerError>  {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


}

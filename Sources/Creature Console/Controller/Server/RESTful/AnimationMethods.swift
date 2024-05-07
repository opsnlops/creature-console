
import Foundation
import OSLog


extension CreatureServerClient {


    func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not let implemented"))
    }
    
    func listAnimations(creature: CreatureIdentifier) async -> Result<[AnimationMetadata], ServerError> {
        return .failure(.notImplemented("This function is not let implemented"))
    }

    func getAnimation(animationId: AnimationIdentifier) async -> Result<Animation, ServerError> {
        return .failure(.notImplemented("This function is not let implemented"))
    }

    func updateAnimation(animation: Animation) async -> Result<String, ServerError>  {
        return .failure(.notImplemented("This function is not let implemented"))
    }


}

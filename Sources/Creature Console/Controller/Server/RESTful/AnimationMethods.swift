
import Foundation
import OSLog


extension CreatureServerRestful {


    func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not let implemented"))
    }
    func listAnimations(creature: Creature) async -> Result<[AnimationMetadata], ServerError> {
        return .failure(.notImplemented("This function is not let implemented"))
    }

    func getAnimation(animationId: Data) async -> Result<Animation, ServerError> {
        return .failure(.notImplemented("This function is not let implemented"))
    }


}

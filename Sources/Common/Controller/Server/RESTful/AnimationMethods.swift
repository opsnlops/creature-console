
import Foundation
import OSLog


extension CreatureServerClient {


    public func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }
    
    public func listAnimations(creatureId: CreatureIdentifier) async -> Result<[AnimationMetadata], ServerError> {

        logger.debug("attempting to get all of the animation metadatas for creature \(creatureId)")

        guard let url = URL(string: makeBaseURL(.http) + "/animation") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: AnimationMetadataListDTO.self).map { $0.items }

    }

    public func getAnimation(animationId: AnimationIdentifier) async -> Result<Animation, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    public func updateAnimation(animation: Animation) async -> Result<String, ServerError>  {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


}

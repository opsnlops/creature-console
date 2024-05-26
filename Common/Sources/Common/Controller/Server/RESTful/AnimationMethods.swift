import Foundation
import Logging

extension CreatureServerClient {


    public func saveAnimation(animation: Animation) async -> Result<String, ServerError> {

        logger.debug("attempting to save animatiom \(animation.metadata.title) on server")

        // Construct the URL
        guard let url = URL(string: makeBaseURL(.http) + "/animation") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        logger.debug("calling sendData() now...")
        let returnObject = await sendData(
            url, method: "POST", body: animation, returnType: Animation.self)
        logger.debug("...and we're back!")

        // Yay we got something back
        switch returnObject {

        case .success(let animation):
            logger.info("successful saved animation to server")
            return .success("Saved '\(animation.metadata.title)' to server")

        case .failure(let error):
            logger.warning(
                "unable to save animation to server: \(error.localizedDescription)")
            return .failure(error)
        }


    }

    public func listAnimations(creatureId: CreatureIdentifier?) async -> Result<
        [AnimationMetadata], ServerError
    > {

        logger.debug(
            "attempting to get all of the animation metadatas for creature \(creatureId ?? "everyone")"
        )

        guard let url = URL(string: makeBaseURL(.http) + "/animation") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: AnimationMetadataListDTO.self).map { $0.items }

    }

    public func getAnimation(animationId: AnimationIdentifier) async -> Result<
        Animation, ServerError
    > {

        logger.debug("attempting to load animation \(animationId)")

        guard let url = URL(string: makeBaseURL(.http) + "/animation/\(animationId)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: Animation.self)
    }


}

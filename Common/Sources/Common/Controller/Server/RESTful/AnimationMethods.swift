import Foundation
import Logging

extension CreatureServerClient {


    public func playStoredAnimation(animationId: AnimationIdentifier, universe: UniverseIdentifier)
        async -> Result<String, ServerError>
    {

        logger.debug(
            "attempting to play an already-stored animation \(animationId) on universe \(universe)")

        // Construct the URL
        guard let url = URL(string: makeBaseURL(.http) + "/animation/play") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = PlayAnimationRequestDto(animation_id: animationId, universe: universe)

        return await sendData(url, method: "POST", body: requestBody, returnType: StatusDTO.self)
            .map { $0.message }
    }

    public func interruptWithAnimation(
        animationId: AnimationIdentifier, universe: UniverseIdentifier, resumePlaylist: Bool = true
    ) async -> Result<String, ServerError> {

        logger.debug(
            "attempting to interrupt with animation \(animationId) on universe \(universe), resumePlaylist: \(resumePlaylist)"
        )

        // Construct the URL
        guard let url = URL(string: makeBaseURL(.http) + "/animation/interrupt") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = PlayAnimationRequestDto(
            animation_id: animationId, universe: universe, resumePlaylist: resumePlaylist)

        return await sendData(url, method: "POST", body: requestBody, returnType: StatusDTO.self)
            .map { $0.message }
    }


    public func saveAnimation(animation: Animation) async -> Result<String, ServerError> {

        logger.debug("attempting to save animation \(animation.metadata.title) on server")

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

    public func listAnimations() async -> Result<
        [AnimationMetadata], ServerError
    > {

        logger.debug(
            "attempting to get all of the animation metadatas"
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

    private func sendAdHocAnimationRequest(
        path: String, body: CreateAdHocAnimationRequestDTO
    ) async -> Result<JobCreatedResponse, ServerError> {

        guard let url = URL(string: makeBaseURL(.http) + path) else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(url, method: "POST", body: body, returnType: JobCreatedResponse.self)
    }

    public func createAdHocSpeechAnimation(
        creatureId: CreatureIdentifier, text: String, resumePlaylist: Bool = true
    ) async -> Result<JobCreatedResponse, ServerError> {
        let request = CreateAdHocAnimationRequestDTO(
            creatureId: creatureId, text: text, resumePlaylist: resumePlaylist)
        return await sendAdHocAnimationRequest(path: "/animation/ad-hoc", body: request)
    }

    public func prepareAdHocSpeechAnimation(
        creatureId: CreatureIdentifier, text: String, resumePlaylist: Bool = true
    ) async -> Result<JobCreatedResponse, ServerError> {
        let request = CreateAdHocAnimationRequestDTO(
            creatureId: creatureId, text: text, resumePlaylist: resumePlaylist)
        return await sendAdHocAnimationRequest(path: "/animation/ad-hoc/prepare", body: request)
    }

    public func triggerPreparedAdHocSpeech(
        animationId: AnimationIdentifier, resumePlaylist: Bool = true
    ) async -> Result<String, ServerError> {
        guard let url = URL(string: makeBaseURL(.http) + "/animation/ad-hoc/play") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = TriggerAdHocAnimationRequestDTO(
            animationId: animationId, resumePlaylist: resumePlaylist)

        return await sendData(url, method: "POST", body: requestBody, returnType: StatusDTO.self)
            .map { $0.message }
    }
}

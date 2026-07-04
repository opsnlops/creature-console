import Foundation
import Logging

private struct EmptyBody: Encodable {}

extension CreatureServerClient {


    public func playStoredAnimation(animationId: AnimationIdentifier, universe: UniverseIdentifier)
        async -> Result<String, ServerError>
    {

        logger.debug(
            "attempting to play an already-stored animation \(animationId) on universe \(universe)")

        let requestBody = PlayAnimationRequestDto(animation_id: animationId, universe: universe)

        return await sendData(
            path: "/animation/play", method: "POST", body: requestBody, returnType: StatusDTO.self
        )
        .map { $0.message }
    }

    public func interruptWithAnimation(
        animationId: AnimationIdentifier, universe: UniverseIdentifier, resumePlaylist: Bool = true
    ) async -> Result<String, ServerError> {

        logger.debug(
            "attempting to interrupt with animation \(animationId) on universe \(universe), resumePlaylist: \(resumePlaylist)"
        )

        let requestBody = PlayAnimationRequestDto(
            animation_id: animationId, universe: universe, resumePlaylist: resumePlaylist)

        return await sendData(
            path: "/animation/interrupt", method: "POST", body: requestBody,
            returnType: StatusDTO.self
        )
        .map { $0.message }
    }


    public func saveAnimation(animation: Animation) async -> Result<String, ServerError> {

        logger.debug("attempting to save animation \(animation.metadata.title) on server")

        logger.debug("calling sendData() now...")
        let returnObject = await sendData(
            path: "/animation", method: "POST", body: animation, returnType: Animation.self)
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

        return await fetchData(path: "/animation", returnType: AnimationMetadataListDTO.self).map {
            $0.items
        }

    }

    public func getAnimation(animationId: AnimationIdentifier) async -> Result<
        Animation, ServerError
    > {

        logger.debug("attempting to load animation \(animationId)")

        return await fetchData(path: "/animation/\(animationId)", returnType: Animation.self)
    }

    public func deleteAnimation(animationId: AnimationIdentifier) async -> Result<
        String, ServerError
    > {
        logger.debug("attempting to delete animation \(animationId)")

        return await sendData(
            path: "/animation/\(animationId)", method: "DELETE", body: EmptyBody(),
            returnType: StatusDTO.self
        )
        .map { $0.message }
    }

    public func generateLipSyncForAnimation(animationId: AnimationIdentifier)
        async -> Result<JobCreatedResponse, ServerError>
    {

        logger.debug("queue lip sync generation for animation \(animationId)")

        let requestBody = RegenerateLipSyncRequestDTO(animationId: animationId)

        return await sendData(
            path: "/animation/generate-lipsync", method: "POST", body: requestBody,
            returnType: JobCreatedResponse.self)
    }

    public func getAdHocAnimation(animationId: AnimationIdentifier) async -> Result<
        Animation, ServerError
    > {

        logger.debug("attempting to load ad-hoc animation \(animationId)")

        return await fetchData(path: "/animation/ad-hoc/\(animationId)", returnType: Animation.self)
    }

    public func listAdHocAnimations() async -> Result<[AdHocAnimationSummary], ServerError> {

        logger.debug("attempting to load ad-hoc animations")

        return await fetchData(path: "/animation/ad-hoc", returnType: AdHocAnimationListDTO.self)
            .map { $0.items }
    }

    private func sendAdHocAnimationRequest(
        path: String, body: CreateAdHocAnimationRequestDTO
    ) async -> Result<JobCreatedResponse, ServerError> {

        return await sendData(
            path: path, method: "POST", body: body, returnType: JobCreatedResponse.self)
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

    // MARK: - Streaming Ad-Hoc Speech Session

    /// Start a streaming ad-hoc speech session. Returns a session ID.
    public func startStreamingAdHocSpeech(
        creatureId: CreatureIdentifier, resumePlaylist: Bool = true
    ) async -> Result<StreamingAdHocStartResponse, ServerError> {
        let body = StreamingAdHocStartRequest(
            creatureId: creatureId, resumePlaylist: resumePlaylist)
        return await sendData(
            path: "/animation/ad-hoc-stream/start", method: "POST", body: body,
            returnType: StreamingAdHocStartResponse.self)
    }

    /// Add a text chunk (sentence) to an active streaming session.
    public func addStreamingAdHocText(
        sessionId: String, text: String
    ) async -> Result<StreamingAdHocTextResponse, ServerError> {
        let body = StreamingAdHocTextRequest(sessionId: sessionId, text: text)
        return await sendData(
            path: "/animation/ad-hoc-stream/text", method: "POST", body: body,
            returnType: StreamingAdHocTextResponse.self)
    }

    /// Finish a streaming session — synthesizes speech, builds animation, plays it.
    public func finishStreamingAdHocSpeech(
        sessionId: String
    ) async -> Result<StreamingAdHocFinishResponse, ServerError> {
        let body = StreamingAdHocFinishRequest(sessionId: sessionId)
        return await sendData(
            path: "/animation/ad-hoc-stream/finish", method: "POST", body: body,
            returnType: StreamingAdHocFinishResponse.self)
    }

    public func triggerPreparedAdHocSpeech(
        animationId: AnimationIdentifier, resumePlaylist: Bool = true
    ) async -> Result<String, ServerError> {
        let requestBody = TriggerAdHocAnimationRequestDTO(
            animationId: animationId, resumePlaylist: resumePlaylist)

        return await sendData(
            path: "/animation/ad-hoc/play", method: "POST", body: requestBody,
            returnType: StatusDTO.self
        )
        .map { $0.message }
    }
}

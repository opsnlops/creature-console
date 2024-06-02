import Foundation
import Logging

extension CreatureServerClient {


    /**
     List all of the voices that we have access to on the ElevenLabs' API
     */
    public func listAvailableVoices() async -> Result<[Voice], ServerError> {

        logger.debug("attempting to get all of the voices that are available to us")

        guard let url = URL(string: makeBaseURL(.http) + "/voice/list-available") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: VoiceListDTO.self).map { $0.items }
    }

    /**
     Get the current status of our elevenlabs.io subscription
     */
    public func getVoiceSubscriptionStatus() async -> Result<VoiceSubscriptionStatus, ServerError> {

        logger.debug("attempting to get the current state of our elevenlabs.io subscription...")

        guard let url = URL(string: makeBaseURL(.http) + "/voice/subscription") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: VoiceSubscriptionStatus.self)
    }

    /**
     Ask the server to make a new speech sound file for a given creature
     */
    public func createCreatureSpeechSoundFile(
        creatureId: CreatureIdentifier, title: String, text: String
    ) async -> Result<CreatureSpeechResponseDTO, ServerError> {

        logger.debug("asking the server to request a new creature speech sound file")

        guard let url = URL(string: makeBaseURL(.http) + "/voice") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = MakeSoundFileRequestDTO(creature_id: creatureId, title: title, text: text)

        return await sendData(
            url, method: "POST", body: requestBody, returnType: CreatureSpeechResponseDTO.self)
    }


}

import Foundation
import Logging

extension CreatureServerClient {


    /**
     List all of the voices that we have access to on the ElevenLabs' API
     */
    public func listAvailableVoices() async -> Result<[Voice], ServerError> {

        logger.debug("attempting to get all of the voices that are available to us")

        return await fetchData(path: "/voice/list-available", returnType: VoiceListDTO.self).map {
            $0.items
        }
    }

    /**
     Get the current status of our elevenlabs.io subscription
     */
    public func getVoiceSubscriptionStatus() async -> Result<VoiceSubscriptionStatus, ServerError> {

        logger.debug("attempting to get the current state of our elevenlabs.io subscription...")

        return await fetchData(
            path: "/voice/subscription", returnType: VoiceSubscriptionStatus.self)
    }

    /**
     Ask the server to make a new speech sound file for a given creature.
    
     Server 3.23.0+: async job (long text can take minutes). The job's completion
     result is a `CreatureSpeechResponseDTO`.
     */
    public func createCreatureSpeechSoundFile(
        creatureId: CreatureIdentifier, title: String, text: String
    ) async -> Result<JobCreatedResponse, ServerError> {

        logger.debug("asking the server to request a new creature speech sound file")

        let requestBody = MakeSoundFileRequestDTO(creature_id: creatureId, title: title, text: text)

        return await sendData(
            path: "/voice", method: "POST", body: requestBody, returnType: JobCreatedResponse.self)
    }


}

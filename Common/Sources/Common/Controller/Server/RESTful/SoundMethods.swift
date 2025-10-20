import Foundation
import Logging

extension CreatureServerClient {


    /**
     List all of the sounds on the server
     */
    public func listSounds() async -> Result<[Sound], ServerError> {

        logger.debug("attempting to get all of the sounds")

        guard let url = URL(string: makeBaseURL(.http) + "/sound") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: SoundListDTO.self).map { $0.items }
    }

    /**
     Generate a lip sync JSON file for a sound on the server.
     */
    public func generateLipSync(
        for fileName: String,
        allowOverwrite: Bool
    ) async -> Result<String, ServerError> {

        logger.debug(
            "attempting to generate lip sync for \(fileName) (allow overwrite: \(allowOverwrite ? "yes" : "no"))"
        )

        guard let url = URL(string: makeBaseURL(.http) + "/sound/generate-lipsync") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = GenerateLipSyncRequestDTO(
            soundFile: fileName, allowOverwrite: allowOverwrite)

        return await sendDataExpectingString(url, body: requestBody)
    }

    /**
     Play one of the sounds on the server
     */
    public func playSound(_ fileName: String) async -> Result<String, ServerError> {

        logger.debug("attempting play sound \(fileName) on server")

        // Construct the URL
        guard let url = URL(string: makeBaseURL(.http) + "/sound/play") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        // No body is needed for this one
        //struct EmptyBody: Encodable {}

        let requestBody = PlaySoundRequestDTO(file_name: fileName)

        return await sendData(url, method: "POST", body: requestBody, returnType: StatusDTO.self)
            .map { $0.message }
    }

    /**
     Returns the URL to a sound file on the server
     */
    public func getSoundURL(_ fileName: String) -> Result<URL, ServerError> {

        logger.debug("attempting to get sound URI for \(fileName)")

        guard let url = URL(string: makeBaseURL(.http) + "/sound/" + fileName) else {
            return .failure(.serverError("unable to make base URL"))
        }

        logger.debug("Sound file URL: \(url)")
        return .success(url)
    }

}

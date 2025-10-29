import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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

    public func listAdHocSounds() async -> Result<[AdHocSoundEntry], ServerError> {

        logger.debug("attempting to get ad-hoc/generated sounds")

        guard let url = URL(string: makeBaseURL(.http) + "/sound/ad-hoc") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: AdHocSoundListDTO.self).map { $0.items }
    }

    /**
     Generate a lip sync JSON file for a sound on the server.
     */
    public func generateLipSync(
        for fileName: String,
        allowOverwrite: Bool
    ) async -> Result<JobCreatedResponse, ServerError> {

        logger.debug(
            "attempting to generate lip sync for \(fileName) (allow overwrite: \(allowOverwrite ? "yes" : "no"))"
        )

        guard let url = URL(string: makeBaseURL(.http) + "/sound/generate-lipsync") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = GenerateLipSyncRequestDTO(
            soundFile: fileName, allowOverwrite: allowOverwrite)

        return await sendData(
            url,
            method: "POST",
            body: requestBody,
            returnType: JobCreatedResponse.self
        )
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

    public func getAdHocSoundURL(_ fileName: String) -> Result<URL, ServerError> {

        logger.debug("attempting to get ad-hoc sound URI for \(fileName)")

        guard let url = URL(string: makeBaseURL(.http) + "/sound/ad-hoc/" + fileName) else {
            return .failure(.serverError("unable to make base URL"))
        }

        logger.debug("Ad-hoc sound file URL: \(url)")
        return .success(url)
    }

}

import Foundation
import Logging

extension CreatureServerClient {


    /**
     List all of the sounds on the server
     */
    public func listSounds() async -> Result<[Sound], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL(.http) + "/sound") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: SoundListDTO.self).map { $0.items }
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

}

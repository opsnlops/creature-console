import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private func parseFilenameFromContentDisposition(_ header: String?) -> String? {
    guard let header else { return nil }

    let segments = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    for segment in segments {
        let lowercased = segment.lowercased()
        guard lowercased.starts(with: "filename=") else { continue }

        let valueStartIndex = segment.index(segment.startIndex, offsetBy: "filename=".count)
        var filename = String(segment[valueStartIndex...])

        if filename.hasPrefix("\"") && filename.hasSuffix("\"") && filename.count >= 2 {
            filename.removeFirst()
            filename.removeLast()
        }

        return filename
    }

    return nil
}

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
     Generate lip sync JSON by uploading a WAV file directly to the server.
     */
    public func generateLipSyncUpload(
        fileName: String,
        wavData: Data
    ) async -> Result<LipSyncUploadResponse, ServerError> {

        logger.debug(
            "attempting to generate lip sync from uploaded data for \(fileName) (\(wavData.count) bytes)")

        guard let encodedName = urlEncode(fileName) else {
            return .failure(.dataFormatError("unable to encode filename for lip sync upload"))
        }

        guard let url = URL(string: makeBaseURL(.http) + "/sound/generate-lipsync/upload?filename=\(encodedName)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        var request = createConfiguredURLRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response from \(url)")
                return .failure(.serverError("Invalid response from \(url)"))
            }

            let decoder = JSONDecoder()

            switch httpResponse.statusCode {
            case 200:
                let suggestedFilename = parseFilenameFromContentDisposition(
                    httpResponse.value(forHTTPHeaderField: "Content-Disposition"))
                return .success(
                    LipSyncUploadResponse(
                        data: data,
                        suggestedFilename: suggestedFilename))

            case 400, 403, 404, 422, 500:
                if let status = try? decoder.decode(StatusDTO.self, from: data) {
                    let message = status.message
                    let error: ServerError
                    switch httpResponse.statusCode {
                    case 400, 422:
                        error = .dataFormatError(message)
                    case 404:
                        error = .notFound(message)
                    default:
                        error = .serverError(message)
                    }
                    return .failure(error)
                } else {
                    return .failure(
                        .serverError("Server returned status \(httpResponse.statusCode)"))
                }

            default:
                return .failure(.serverError("Unexpected status code \(httpResponse.statusCode)"))
            }

        } catch {
            logger.error("Request error: \(error.localizedDescription)")
            return .failure(.serverError("Request error: \(error.localizedDescription)"))
        }
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

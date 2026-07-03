import Foundation
import Logging

/// The server addresses sounds by **basename** — it resolves the actual file by
/// walking the permanent tree (dialog/ renders) and the ad-hoc tree. Callers may
/// hold a stored reference that's a relative or absolute path (e.g.
/// `animation.metadata.sound_file`, which is `dialog/<uuid>.wav` for permanent
/// renders and an absolute `/tmp/creature-adhoc/…` path for ad-hoc ones). Reduce
/// any such reference to its last path component before putting it in a URL, so a
/// path never leaks in as extra route segments (which oatpp can't map).
func soundBasename(_ stored: String) -> String {
    stored.split(separator: "/").last.map(String.init) ?? stored
}

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
            "attempting to generate lip sync from uploaded data for \(fileName) (\(wavData.count) bytes)"
        )

        guard let encodedName = urlEncode(fileName) else {
            return .failure(.dataFormatError("unable to encode filename for lip sync upload"))
        }

        guard
            let url = URL(
                string: makeBaseURL(.http)
                    + "/sound/generate-lipsync/upload?filename=\(encodedName)")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let result = await sendBinaryDataResponse(
            url,
            method: "POST",
            body: wavData,
            contentType: "audio/wav",
            successStatusCodes: [200]
        )

        switch result {
        case .success(let response):
            return .success(
                LipSyncUploadResponse(
                    data: response.data,
                    suggestedFilename: parseFilenameFromContentDisposition(
                        response.contentDisposition)))
        case .failure(let error):
            return .failure(error)
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

        let name = soundBasename(fileName)
        guard let encodedName = urlEncode(name),
            let url = URL(string: makeBaseURL(.http) + "/sound/" + encodedName)
        else {
            return .failure(.serverError("unable to make base URL"))
        }

        logger.debug("Sound file URL: \(url)")
        return .success(url)
    }

    public func getAdHocSoundURL(_ fileName: String) -> Result<URL, ServerError> {

        logger.debug("attempting to get ad-hoc sound URI for \(fileName)")

        let name = soundBasename(fileName)
        guard let encodedName = urlEncode(name),
            let url = URL(string: makeBaseURL(.http) + "/sound/ad-hoc/" + encodedName)
        else {
            return .failure(.serverError("unable to make base URL"))
        }

        logger.debug("Ad-hoc sound file URL: \(url)")
        return .success(url)
    }

    /**
     Returns the URL of the shareable Ogg/Opus rendition of a sound file (the server
     searches the permanent store, then the ad-hoc store).
     */
    public func getShareableSoundURL(_ fileName: String) -> Result<URL, ServerError> {

        logger.debug("attempting to get shareable sound URL for \(fileName)")

        guard let encodedName = urlEncode(soundBasename(fileName)),
            let url = URL(string: makeBaseURL(.http) + "/sound/shareable/" + encodedName)
        else {
            return .failure(.serverError("unable to make base URL"))
        }

        logger.debug("Shareable sound URL: \(url)")
        return .success(url)
    }

    /**
     Fetch the embedded provenance of a dialog sound file.
    
     Dialog renders carry an iXML chunk describing the source script and channel
     layout (server issue #47). Returns the parsed `DialogProvenance`, or a failure
     (404) when the sound carries no embedded provenance.
     */
    public func fetchDialogProvenance(fileName: String) async -> Result<
        DialogProvenance, ServerError
    > {

        logger.debug("attempting to fetch provenance for \(fileName)")

        guard let encodedName = urlEncode(soundBasename(fileName)),
            let url = URL(string: makeBaseURL(.http) + "/sound/provenance/" + encodedName)
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchDataResponse(url).flatMap { response in
            guard let xml = String(data: response.data, encoding: .utf8) else {
                return .failure(.dataFormatError("provenance response was not valid UTF-8"))
            }
            guard let provenance = DialogProvenance(iXML: xml) else {
                return .failure(.dataFormatError("could not parse provenance for \(fileName)"))
            }
            return .success(provenance)
        }
    }

    /// A downloaded shareable rendition of a sound, ready to write to disk.
    public struct ShareableSound: Sendable {
        public let data: Data
        public let suggestedFilename: String
    }

    /**
     Download a shareable Ogg/Opus rendition of a sound file.
    
     The server looks in the permanent sound store first, then the ad-hoc store,
     downmixes multi-channel WAVs to mono, and encodes to Ogg/Opus.
     */
    public func downloadShareableSound(fileName: String) async -> Result<
        ShareableSound, ServerError
    > {

        logger.debug("attempting to download a shareable version of \(fileName)")

        let name = soundBasename(fileName)
        guard let encodedName = urlEncode(name),
            let url = URL(string: makeBaseURL(.http) + "/sound/shareable/" + encodedName)
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchDataResponse(url).map { response in
            let fallback: String
            if let dotIndex = name.lastIndex(of: ".") {
                fallback = String(name[..<dotIndex]) + ".ogg"
            } else {
                fallback = name + ".ogg"
            }
            let suggested =
                parseFilenameFromContentDisposition(response.contentDisposition) ?? fallback
            return ShareableSound(data: response.data, suggestedFilename: suggested)
        }
    }

}

import Foundation
import Logging

private struct EmptyBody: Encodable {}

extension CreatureServerClient {

    // MARK: - URL helpers

    /// Builds an absolute URL from a server-relative path (one that already begins with
    /// `/api/v1/...`, such as a preview `audio_url`).
    ///
    /// `makeBaseURL(.http)` already appends `/api/v1`, so naively concatenating it with a
    /// path that *also* starts with `/api/v1` would double the prefix. This strips the
    /// trailing `/api/v1` from the base before appending.
    public func makeAbsoluteURL(fromRelativePath path: String) -> URL? {
        let base = makeBaseURL(.http)
        let apiSuffix = "/api/v1"
        let root = base.hasSuffix(apiSuffix) ? String(base.dropLast(apiSuffix.count)) : base
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: root + suffix)
    }

    /// Direct URL to the mono preview WAV for a specific cached take. You normally use the
    /// `audio_url` returned by `dialogPreviewMeta` instead; this is here for the CLI and for
    /// reconstructing the URL by hand. `filename` is the generation id (an optional `.wav`
    /// suffix is fine — the server strips it).
    public func dialogPreviewAudioURL(cacheKey: String, filename: String) -> Result<
        URL, ServerError
    > {
        guard
            let url = URL(
                string: makeBaseURL(.http)
                    + "/animation/dialog/preview/audio/\(cacheKey)/\(filename)")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        return .success(url)
    }

    /// Direct URL to a rendition of a specific cached preview take (mono — the server encodes the
    /// cached PCM on demand). Format is a parameter (`SoundRendition`): MP3 for the GUI (plays in
    /// AVFoundation + Slack), Ogg/Opus otherwise. The MP3 variant requires creature-server#58
    /// (`…/preview/share/{key}/{id}.mp3`).
    public func dialogPreviewRenditionURL(
        cacheKey: String, generationId: DialogGenerationIdentifier, as rendition: SoundRendition
    ) -> Result<URL, ServerError> {
        let filename = generationId.uuidString.lowercased() + "." + rendition.fileExtension
        guard
            let url = URL(
                string: makeBaseURL(.http)
                    + "/animation/dialog/preview/share/\(cacheKey)/\(filename)")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        return .success(url)
    }

    // MARK: - DialogScript CRUD

    public func listDialogScripts() async -> Result<[DialogScript], ServerError> {
        logger.debug("attempting to get all of the dialog scripts")

        return await fetchData(
            path: "/animation/dialog/script", returnType: DialogScriptListDTO.self
        )
        .map { $0.items }
    }

    public func getDialogScript(id: DialogScriptIdentifier) async -> Result<
        DialogScript, ServerError
    > {
        logger.debug("attempting to load dialog script \(id)")

        return await fetchData(
            path: "/animation/dialog/script/\(id.uuidString.lowercased())",
            returnType: DialogScript.self)
    }

    /// Creates a new script. The server stamps `id` + timestamps and returns the full record
    /// (HTTP 201). Any `id`/`created_at`/`updated_at` we send is ignored server-side.
    public func createDialogScript(_ script: DialogScript) async -> Result<
        DialogScript, ServerError
    > {
        logger.debug("attempting to create a new dialog script: \(script.title)")

        // Send only the editable fields — the server rejects id/created_at/updated_at.
        return await sendData(
            path: "/animation/dialog/script", method: "POST",
            body: UpsertDialogScriptRequest(script),
            returnType: DialogScript.self)
    }

    /// Replaces an existing script (HTTP 200). The server preserves `created_at` and bumps
    /// `updated_at`. Returns `404` if no script with that id exists (PUT never creates-by-id).
    public func updateDialogScript(_ script: DialogScript) async -> Result<
        DialogScript, ServerError
    > {
        logger.debug("attempting to update dialog script \(script.id)")

        // The id travels in the URL path; the body carries only the editable fields.
        return await sendData(
            path: "/animation/dialog/script/\(script.id.uuidString.lowercased())", method: "PUT",
            body: UpsertDialogScriptRequest(script),
            returnType: DialogScript.self)
    }

    public func deleteDialogScript(id: DialogScriptIdentifier) async -> Result<String, ServerError>
    {
        logger.debug("attempting to delete dialog script \(id)")

        return await sendData(
            path: "/animation/dialog/script/\(id.uuidString.lowercased())", method: "DELETE",
            body: EmptyBody(), returnType: StatusDTO.self
        ).map { $0.message }
    }

    /// Shape-checks a script without saving (always HTTP 200). Use for debounced live form
    /// validation. `missingCreatureIds` are soft warnings; `errorMessages` are hard errors.
    public func validateDialogScript(_ script: DialogScript) async -> Result<
        DialogScriptValidationDTO, ServerError
    > {
        return await sendData(
            path: "/animation/dialog/script/validate", method: "POST", body: script,
            returnType: DialogScriptValidationDTO.self)
    }

    // MARK: - Render

    /// Renders a scene into a multi-track Animation (async job, HTTP 202). Subscribe to the
    /// WebSocket and filter `job-progress`/`job-complete` on the returned `jobId`.
    public func renderDialog(_ request: DialogRequest) async -> Result<
        JobCreatedResponse, ServerError
    > {
        logger.debug("attempting to render a dialog (persistence: \(request.persistence.rawValue))")

        return await sendData(
            path: "/animation/dialog", method: "POST", body: request,
            returnType: JobCreatedResponse.self)
    }

    // MARK: - Preview

    /// Generates (or loads from cache) a preview take and returns metadata + a relative audio
    /// URL. Build the playable URL with `makeAbsoluteURL(fromRelativePath:)`.
    /// How a preview-meta request resolved: cache hits come back immediately with the
    /// meta; fresh generation is queued as a job (server 3.23.0+) whose completion
    /// result carries the same meta DTO.
    public enum DialogPreviewMetaOutcome: Sendable {
        case meta(DialogPreviewMetaDTO)
        case queued(JobCreatedResponse)
    }

    public func dialogPreviewMeta(_ request: DialogPreviewRequest) async -> Result<
        DialogPreviewMetaOutcome, ServerError
    > {
        return await sendDataResponse(
            path: "/animation/dialog/preview/meta", method: "POST", body: request
        )
        .flatMap { response in
            if response.statusCode == 202 {
                return decodeResponse(response.data, returnType: JobCreatedResponse.self)
                    .map { .queued($0) }
            }
            return decodeResponse(response.data, returnType: DialogPreviewMetaDTO.self)
                .map { .meta($0) }
        }
    }

    /// Cheap cache check — which generations already exist for these turns. Returns `.notFound`
    /// when nothing is cached yet (the endpoint 404s in that case).
    public func dialogPreviewLookup(_ request: DialogPreviewRequest) async -> Result<
        DialogPreviewLookupDTO, ServerError
    > {
        return await sendData(
            path: "/animation/dialog/preview/lookup", method: "POST", body: request,
            returnType: DialogPreviewLookupDTO.self)
    }

    /// Fetches the full 17-channel WAV bytes (S16 LE @ 48 kHz, each creature in its
    /// `audio_channel` lane) for inspection in Audacity. Reuses any cached generation.
    /// Queue assembly of the 17-channel WAV (server 3.23.0+: always an async job — long
    /// scenes produce enormous WAVs). The job's completion result is a
    /// `DialogPreviewExportResult` naming the file in the ad-hoc sound bucket.
    public func dialogPreviewMultichannel(_ request: DialogPreviewRequest) async -> Result<
        JobCreatedResponse, ServerError
    > {
        return await sendData(
            path: "/animation/dialog/preview/multichannel", method: "POST", body: request,
            returnType: JobCreatedResponse.self)
    }

    /// Downloads the raw bytes at a URL (e.g. the mono preview WAV) using the configured
    /// request headers. Use with `makeAbsoluteURL(fromRelativePath:)` on a preview `audio_url`.
    public func downloadRawData(from url: URL) async -> Result<Data, ServerError> {
        switch await fetchDataResponse(url) {
        case .success(let response):
            return .success(response.data)
        case .failure(.notFound):
            return .failure(.notFound("Audio not found (it may have been swept)"))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Raw POST helper

    /// POSTs a JSON body and returns the raw response bytes (for endpoints that return binary
    /// data, like the multichannel WAV). On error, attempts to decode a `StatusDTO` message.
    private func postForRawData<U: Encodable>(_ url: URL, body: U) async -> Result<
        Data, ServerError
    > {
        await sendDataResponse(url, method: "POST", body: body).map { $0.data }
    }
}

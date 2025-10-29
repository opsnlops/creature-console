import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private struct EmptyBody: Encodable {}

extension CreatureServerClient {

    public func stopPlayingPlaylist(universe: UniverseIdentifier) async -> Result<
        String, ServerError
    > {
        // Construct the URL
        guard let url = URL(string: makeBaseURL(.http) + "/playlist/stop") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = PlaylistStopRequestDTO(universe: universe)

        return await sendData(url, method: "POST", body: requestBody, returnType: StatusDTO.self)
            .map { $0.message }
    }

    public func getPlaylist(playlistId: PlaylistIdentifier) async -> Result<
        Playlist, ServerError
    > {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


    public func startPlayingPlaylist(
        universe: UniverseIdentifier,
        playlistId: PlaylistIdentifier
    ) async -> Result<String, ServerError> {

        logger.debug("attempting start a playlist")

        // Construct the URL
        guard let url = URL(string: makeBaseURL(.http) + "/playlist/start") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let requestBody = PlaylistRequestDTO(playlist_id: playlistId, universe: universe)

        return await sendData(url, method: "POST", body: requestBody, returnType: StatusDTO.self)
            .map { $0.message }

    }


    public func getAllPlaylists() async -> Result<[Playlist], ServerError> {
        logger.debug("attempting to get all the playlists")

        guard let url = URL(string: makeBaseURL(.http) + "/playlist") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: PlaylistListDTO.self).map { $0.items }

    }

    public func createPlaylist(_ playlist: Playlist) async -> Result<String, ServerError> {
        logger.debug("attempting to create a new playlist")
        return await upsertPlaylist(playlist)
    }

    public func updatePlaylist(_ playlist: Playlist) async -> Result<String, ServerError> {
        logger.debug("attempting to update playlist: \(playlist.id)")
        return await upsertPlaylist(playlist)
    }

    private func upsertPlaylist(_ playlist: Playlist) async -> Result<String, ServerError> {
        guard let url = URL(string: makeBaseURL(.http) + "/playlist") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        // Try to send as StatusDTO first, but handle the case where server returns different format
        let result = await sendData(url, method: "POST", body: playlist, returnType: StatusDTO.self)

        switch result {
        case .success(let status):
            return .success(status.message)
        case .failure(let error):
            // If decoding failed but it might be a successful operation, let's try a more flexible approach
            self.logger.warning(
                "StatusDTO decoding failed: \(error.localizedDescription), trying raw response")
            return await sendDataFlexible(url, method: "POST", body: playlist)
        }
    }

    // Flexible version that can handle different server response formats
    private func sendDataFlexible<U: Encodable>(_ url: URL, method: String = "POST", body: U) async
        -> Result<String, ServerError>
    {
        do {
            let encoder = JSONEncoder()
            let requestBody = try encoder.encode(body)

            var request = createConfiguredURLRequest(for: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response from \(url)")
                return .failure(.serverError("Invalid response from \(url)"))
            }

            switch httpResponse.statusCode {
            case 200, 201:
                // Success - try to parse response or return generic success message
                if data.isEmpty {
                    return .success("Playlist updated successfully")
                }

                // Try to decode as StatusDTO
                if let status = try? JSONDecoder().decode(StatusDTO.self, from: data) {
                    return .success(status.message)
                }

                // Try to decode as plain string
                if let message = String(data: data, encoding: .utf8) {
                    return .success(message)
                }

                // Fallback to generic success
                return .success("Playlist updated successfully")

            case 400:
                return .failure(.dataFormatError("Bad request"))
            case 404:
                return .failure(.notFound("Playlist not found"))
            case 500:
                return .failure(.serverError("Internal server error"))
            default:
                return .failure(.serverError("HTTP \(httpResponse.statusCode)"))
            }

        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            return .failure(.communicationError("Network error: \(error.localizedDescription)"))
        }
    }

    public func deletePlaylist(_ playlistId: PlaylistIdentifier) async -> Result<
        String, ServerError
    > {
        logger.debug("attempting to delete playlist: \(playlistId)")

        guard let url = URL(string: makeBaseURL(.http) + "/playlist/\(playlistId)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(url, method: "DELETE", body: EmptyBody(), returnType: StatusDTO.self)
            .map { $0.message }
    }

}

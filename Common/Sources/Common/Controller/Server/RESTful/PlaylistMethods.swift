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

        let result = await sendDataResponse(
            url,
            method: "POST",
            body: playlist,
            successStatusCodes: [200, 201]
        )

        switch result {
        case .success(let response):
            return playlistUpsertMessage(from: response.data)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func playlistUpsertMessage(from data: Data) -> Result<String, ServerError> {
        guard !data.isEmpty else {
            return .success("Playlist updated successfully")
        }

        let decoder = makeJSONDecoder()
        if let status = try? decoder.decode(StatusDTO.self, from: data) {
            return .success(status.message)
        }

        if let playlist = try? decoder.decode(Playlist.self, from: data) {
            return .success("Saved '\(playlist.name)' to server")
        }

        if let message = String(data: data, encoding: .utf8) {
            return .success(message)
        }

        return .success("Playlist updated successfully")
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

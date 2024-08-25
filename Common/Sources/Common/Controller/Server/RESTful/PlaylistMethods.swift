import Foundation
import Logging

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

}

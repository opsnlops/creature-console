import Foundation
import Logging

extension CreatureServerClient {

    public func stopPlayingPlaylist(universe: UniverseIdentifier) async throws -> Result<
        String, ServerError
    > {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    public func getPlaylist(playlistId: PlaylistIdentifier) async throws -> Result<
        Playlist, ServerError
    > {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    public func startPlayingPlaylist(
        universe: UniverseIdentifier,
        playlistId: PlaylistIdentifier
    ) async throws -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
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

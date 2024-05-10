
import Foundation
import OSLog


extension CreatureServerClient {

    public func stopPlayingPlaylist(universe: UniverseIdentifier) async throws -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    public func getPlaylist(playistId: PlaylistIdentifier) async throws -> Result<Playlist, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }
    
    public func startPlayingPlaylist(universe: UniverseIdentifier,
                              playlistId: PlaylistIdentifier) async throws -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


}

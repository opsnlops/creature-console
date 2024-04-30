
import Foundation
import OSLog


extension CreatureServerRestful {

    func stopPlayingPlayist(universe: UInt32) async throws -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    func getPlaylist(playistId: Data) async throws -> Result<Playlist, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }
    
    func startPlayingPlaylist(universe: UInt32, playlistId: Data) async throws -> Result<String, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


}

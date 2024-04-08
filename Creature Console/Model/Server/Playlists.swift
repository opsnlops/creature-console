
import Foundation
import SwiftUI
import OSLog
import GRPC


extension CreatureServerClient {
 
        
    /**
     Stop playing a playlist on the server
     */
    func stopPlayingPlayist(universe: UInt32) async throws -> Result<String, ServerError> {
        
        logger.debug("attempting to stop playing a playlist on universe \(universe)")
    
        var request = Server_PlaylistStopRequest()
        request.universe = universe
        
        // Ensure the server is valid
        if let s = server {
            
            do {
            
                // This returns a Server_CreaturePlaylistResponse
                let result = try await s.stopPlaylist(request)
    
                if(result.success) {
                    logger.info("successfully scheduled animation! Server said: \(result.message)")
                    return .success(result.message)
                }
                else {
                    logger.warning("server was not able to stop playback of a playlist? server said: \(result.message)")
                    return .failure(.otherError(result.message))
                }
    
            } catch {
                
                logger.warning("unable to stop playlist playback! Server said: \(error.localizedDescription)")
                return .failure(.otherError(error.localizedDescription))
                
            }
        }
        
        logger.error("The server is nil while attempting to stop playlist playback?")
        return .failure(.communicationError("Server is nil for some reason? 😱"))
    }
    
    
    func getPlaylist(playistId: Data) async throws -> Result<Playlist, ServerError> {
        
        logger.debug("attempting to get a playlist from the server: \(DataHelper.dataToHexString(data: playistId))")
    
        var id = Server_PlaylistIdentifier()
        id.id = playistId
        
        // Ensure the server is valid
        if let s = server {
            
            do {
            
                // This returns a Server_Playlist
                let result = try await s.getPlaylist(id)
                logger.info("loaded playlist \(result.name) from the server")
                return .success(Playlist(fromServerPlaylist: result))
                
            } catch {
                logger.warning("Unable to load playlist! Server said: \(error.localizedDescription)")
                return .failure(.otherError(error.localizedDescription))
                
            }
        }
        
        logger.error("The server is nil while attempting to load a playlist?")
        return .failure(.communicationError("Server is nil while trying to load a playlist? 😱"))
    }
    
    
    func startPlayingPlaylist(universe: UInt32, playlistId: Data) async throws -> Result<String, ServerError> {
        
        logger.info("attempting to start a playlist playing back on the server. universe: \(universe), playlist:  \(DataHelper.dataToHexString(data: playlistId))")
        
        var request = Server_PlaylistRequest()
        
        var pId = Server_PlaylistIdentifier()
        pId.id = playlistId
        
        request.universe = universe
        request.playlistID = pId
        
        // Ensure the server is valid
        if let s = server {
            
            do {
            
                // This returns a Server_CreaturePlaylistResponse
                let result = try await s.startPlaylist(request)
                
                if(result.success) {
                    logger.info("playlist started successfully")
                    return .success(result.message)
                }
                else {
                    logger.warning("server was unable to start playlist")
                    return .failure(.communicationError(result.message))
                }
                
            } catch {
                logger.warning("Unable to request starting to play a playlist! Server said: \(error.localizedDescription)")
                return .failure(.otherError(error.localizedDescription))
                
            }
        }
        
        logger.error("The server is nil while attempting to load a playlist?")
        return .failure(.communicationError("Server is nil while trying to load a playlist? 😱"))
        
    }
    
}

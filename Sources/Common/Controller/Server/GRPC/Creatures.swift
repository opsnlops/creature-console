
import Foundation
import SwiftUI
import OSLog
import GRPC


extension CreatureServerClient {
    
    
    /**
     Seach for a creature by name
     */
    func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError> {
        
        // Don't search for a blank name
        guard !creatureName.isEmpty else {
            logger.warning("unable to search for an empty creature")
            return .failure(.dataFormatError("creatureName cannot be blank"))
        }
        
        
        logger.info("attempting to search for \(creatureName) from sever")
                
        do {
        
            var name = Server_CreatureName()
            name.name = creatureName
            
            logger.debug("calling searchCreatures() now")
            
            guard let creature = try await server?.searchCreatures(name) else {
                logger.error("No creature named \(creatureName) found.")
                return .failure(.notFound("A creature named \(creatureName) was not found"))
            }
            
            logger.debug("Success getting a creature from the server!")
            return .success(Creature(serverCreature: creature))
        }
        catch {
            logger.error("Unable to search for a creature named \(creatureName): \(error.localizedDescription)")
            return .failure(.serverError("Server said: \(error.localizedDescription), (\(error))"))
        }
    }
    
    /**
     Load a creature by id
     */
    func getCreature(creatureId: Data) async throws -> Result<Creature, ServerError> {
        
        // Make sure there's data to look for
        guard !creatureId.isEmpty && creatureId.count == 12 else {
            logger.warning("creatureId is not 12 bytes long on getCreature()")
            return .failure(.dataFormatError("creatureId must be 12 bytes long"))
        }
        
        // Make this easier to read in error messages
        let idString = DataHelper.dataToHexString(data: creatureId)
        
        logger.info("attempting to load creature with ID \(idString) from the server")
                
        do {
        
            var id = Server_CreatureId()
            id.id = creatureId
            
            logger.debug("calling getCreature() now")
            
            guard let creature = try await server?.getCreature(id) else {
                logger.error("No creature with ID \(idString) found.")
                return .failure(.notFound("A creature with ID \(idString) was not found"))
            }
            
            logger.debug("Success getting creature \(idString) from the server!")
            return .success(Creature(serverCreature: creature))
        }
        catch {
            logger.error("Unable to load a creature by ID \(idString): \(error.localizedDescription)")
            return .failure(.serverError("Server said: \(error.localizedDescription), (\(error))"))
        }
    }
    
    /**
     Returns an array of all of the creatures from the server, sorted by name
     */
    func getAllCreatures() async -> Result<[Creature], ServerError> {
        
        logger.info("attempting to get all of the creatures from the server")
        
        var creatures : [Creature]
        creatures = []
        
        // Default to sorting by name.
        var filter : Server_CreatureFilter
        filter = Server_CreatureFilter()
        filter.sortBy = Server_SortBy.name
        logger.debug("Server_CreatureFilter made and set to name")
        
        do {
    
            guard let list = try await server?.getAllCreatures(filter) else {
                logger.warning("got back zero creatures from the server?? 🤔")
                return .success([]) // Return an empty array
            }
            
            for c in list.creatures {
                creatures.append(Creature(serverCreature: c))
                logger.debug("found creature \(c.name)")
            }
            
            logger.debug("total creatures found: \(creatures.count)")
            return .success(creatures)
            
        } catch let error as GRPC.GRPCStatus {
            
            logger.error("gRPC Error - Code: \(String(describing: error.code)), Message: \(error.message ?? "Unknown error")")
            return .failure(.serverError("gRPC Error - Code: \(String(describing: error.code)), Message: \(error.message ?? "Unknown error")"))
            
        } catch {
            // Dunno what it is, so return an unexpected error
            logger.error("Unknown error: \(error.localizedDescription)")
            return .failure(.unknownError("Unknown error: \(error.localizedDescription)"))
        }
        
    }
}


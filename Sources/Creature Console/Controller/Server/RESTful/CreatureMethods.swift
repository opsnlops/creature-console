
import Foundation
import OSLog


extension CreatureServerClient {

    
    func getAllCreatures() async -> Result<[Creature], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL(.http) + "/creature") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: CreatureListDTO.self).map { $0.items }
        
    }



    func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    func getCreature(creatureId: CreatureIdentifier) async throws -> Result<Creature, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


}

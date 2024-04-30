
import Foundation
import OSLog


extension CreatureServerRestful {

    
    func getAllCreatures() async -> Result<[Creature], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL() + "/creature") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.logger.debug("return code was \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return .failure(.serverError("non-200 return code"))
            }

            do {
                let decoder = JSONDecoder()
                let list = try decoder.decode(CreatureListDTO.self, from: data)

                logger.debug("Found \(list.count) items")

                return .success(list.items)
            } catch {
                return .failure(.serverError(error.localizedDescription))
            }
        } catch {
            return .failure(.serverError(error.localizedDescription))
        }
    }



    func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    func getCreature(creatureId: Data) async throws -> Result<Creature, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

}


import Foundation
import OSLog


extension CreatureServerClient {

    
    func getAllCreatures() async -> Result<[Creature], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL(.http) + "/creature") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("HTTP Error while trying to list known creatures")
                return .failure(.serverError("HTTP error while trying to the the creature list"))
            }

            // It's JSON decoding time!
            let decoder = JSONDecoder()

            do {
                switch(httpResponse.statusCode) {

                case 200:
                    let list = try decoder.decode(CreatureListDTO.self, from: data)
                    logger.debug("Found \(list.count) creatures")
                    return .success(list.items)

                case 404:
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    logger.warning("No creatures found on the remote server: \(status.message)")
                    return .failure(.notFound(status.message))

                case 500:
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    logger.error("Server error while trying to get the list of creatures: \(status.message)")
                    return .failure(.serverError(status.message))

                default:
                    self.logger.error("unexpected return code from \(url) while attempting to get the list of creatures: \(httpResponse.statusCode)")
                    return .failure(.serverError("Unexepcted status code while getting the creature list: \(httpResponse.statusCode)"))
                }

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

    func getCreature(creatureId: CreatureIdentifier) async throws -> Result<Creature, ServerError> {
        return .failure(.notImplemented("This function is not yet implemented"))
    }


}

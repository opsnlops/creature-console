import Foundation
import Logging

extension CreatureServerClient {

    public func getAllCreatures() async -> Result<[Creature], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL(.http) + "/creature") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: CreatureListDTO.self).map { $0.items }

    }

    public func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError>
    {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    public func getCreature(creatureId: CreatureIdentifier) async throws -> Result<
        Creature, ServerError
    > {
        guard let url = URL(string: makeBaseURL(.http) + "/creature/\(creatureId)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: Creature.self)
    }

    public func validateCreatureConfig(rawConfig: String) async -> Result<
        CreatureConfigValidationDTO, ServerError
    > {
        guard let url = URL(string: makeBaseURL(.http) + "/creature/validate") else {
            return .failure(.serverError("unable to make base URL"))
        }
        logger.debug("Using URL: \(url)")

        return await sendRawJson(
            url, method: "POST", rawJson: rawConfig, returnType: CreatureConfigValidationDTO.self)
    }

    public func setIdleEnabled(creatureId: CreatureIdentifier, enabled: Bool) async -> Result<
        Creature, ServerError
    > {
        guard let url = URL(string: makeBaseURL(.http) + "/creature/\(creatureId)/idle") else {
            return .failure(.serverError("unable to make base URL"))
        }
        logger.debug("Using URL: \(url)")

        let requestBody = IdleToggleDTO(enabled: enabled)
        let result = await sendData(
            url, method: "PATCH", body: requestBody, returnType: Creature.self)

        switch result {
        case .success:
            return result
        case .failure(let error):
            if case .serverError(let message) = error, message.contains("Decoding error") {
                do {
                    let fallback = try await getCreature(creatureId: creatureId)
                    switch fallback {
                    case .success:
                        return fallback
                    case .failure:
                        return result
                    }
                } catch {
                    return result
                }
            }
            return result
        }
    }

}

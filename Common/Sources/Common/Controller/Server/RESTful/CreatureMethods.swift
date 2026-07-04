import Foundation
import Logging

extension CreatureServerClient {

    public func getAllCreatures() async -> Result<[Creature], ServerError> {

        logger.debug("attempting to get all of the creatures")

        return await fetchData(path: "/creature", returnType: CreatureListDTO.self).map { $0.items }

    }

    public func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError>
    {
        return .failure(.notImplemented("This function is not yet implemented"))
    }

    public func getCreature(creatureId: CreatureIdentifier) async throws -> Result<
        Creature, ServerError
    > {
        return await fetchData(path: "/creature/\(creatureId)", returnType: Creature.self)
    }

    /// Fetches a creature's complete stored configuration as raw JSON, exactly as the
    /// server persists it (every field, `_id` stripped) — for disaster-recovery export.
    /// Returns the body verbatim rather than decoding into `Creature`, which is a trimmed
    /// view and would silently drop fields like motors and servo settings.
    public func exportCreature(creatureId: CreatureIdentifier) async -> Result<String, ServerError>
    {
        return await fetchDataResponse(path: "/creature/\(creatureId)/export").map {
            String(decoding: $0.data, as: UTF8.self)
        }
    }

    public func validateCreatureConfig(rawConfig: String) async -> Result<
        CreatureConfigValidationDTO, ServerError
    > {
        return await sendRawJson(
            path: "/creature/validate", method: "POST", rawJson: rawConfig,
            returnType: CreatureConfigValidationDTO.self)
    }

    public func setIdleEnabled(creatureId: CreatureIdentifier, enabled: Bool) async -> Result<
        Creature, ServerError
    > {
        let requestBody = IdleToggleDTO(enabled: enabled)
        return await sendData(
            path: "/creature/\(creatureId)/idle", method: "PATCH", body: requestBody,
            returnType: Creature.self)
    }

}

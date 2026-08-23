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

    /// Create or update a creature from its configuration JSON, verbatim.
    ///
    /// **This is the lossless path, and the one to use when importing a file.** The server
    /// stores the JSON object it receives and `REPLACE`s the whole document, so anything the
    /// request doesn't carry is gone — including fields the Console's trimmed `Creature`
    /// model doesn't know about, like motors and servo settings. Send the bytes you were
    /// given rather than a re-encoded model.
    public func upsertCreature(rawConfig: String) async -> Result<Creature, ServerError> {
        logger.debug("attempting to upsert a creature from raw config JSON")

        return await sendRawJson(
            path: "/creature", method: "POST", rawJson: rawConfig, returnType: Creature.self)
    }

    /// Create or update a creature from the typed model.
    ///
    /// Only the configuration travels — never the `runtime` block, which is the server's own
    /// view of what the creature is doing. Absent optionals are omitted rather than sent as
    /// `null`; the server's codec rejects `null` for an optional configuration value.
    ///
    /// - Warning: `Creature` is a *trimmed* view of what the server stores, and the upsert is
    ///   a whole-document replace. Posting a model that was decoded from a fuller stored
    ///   document will drop every field this model doesn't carry. Use
    ///   ``upsertCreature(rawConfig:)`` whenever the original JSON is available.
    public func upsertCreature(_ creature: Creature) async -> Result<Creature, ServerError> {
        logger.debug("attempting to upsert creature \(creature.name) (\(creature.id))")

        switch encodedConfiguration(for: creature) {
        case .success(let rawConfig):
            return await upsertCreature(rawConfig: rawConfig)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Register a creature, and the universe it's currently listening on, from its
    /// configuration JSON verbatim.
    ///
    /// This is the controller-startup path: the config in the request is the source of truth
    /// and gets upserted, while the universe assignment stays in the server's runtime memory.
    /// The endpoint wants the configuration as a *string* rather than a nested object, which
    /// is exactly what a controller has on disk.
    ///
    /// The same whole-document replace applies here as in ``upsertCreature(rawConfig:)``.
    public func registerCreature(rawConfig: String, universe: UniverseIdentifier) async
        -> Result<Creature, ServerError>
    {
        logger.debug("attempting to register a creature on universe \(universe)")

        let requestBody = RegisterCreatureRequestDTO(
            creatureConfig: rawConfig, universe: universe)

        return await sendData(
            path: "/creature/register", method: "POST", body: requestBody,
            returnType: Creature.self)
    }

    /// Register a creature from the typed model.
    ///
    /// - Warning: carries the same trimming caveat as ``upsertCreature(_:)``.
    public func registerCreature(_ creature: Creature, universe: UniverseIdentifier) async
        -> Result<Creature, ServerError>
    {
        logger.debug(
            "attempting to register creature \(creature.name) (\(creature.id)) on universe \(universe)"
        )

        switch encodedConfiguration(for: creature) {
        case .success(let rawConfig):
            return await registerCreature(rawConfig: rawConfig, universe: universe)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// The creature's configuration payload as JSON text — config fields only, absent
    /// optionals omitted.
    private func encodedConfiguration(for creature: Creature) -> Result<String, ServerError> {
        do {
            let encoded = try JSONEncoder().encode(creature.configurationPayload())
            return .success(String(decoding: encoded, as: UTF8.self))
        } catch {
            return .failure(
                .serverError(
                    "Unable to encode creature configuration: \(error.localizedDescription)"))
        }
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

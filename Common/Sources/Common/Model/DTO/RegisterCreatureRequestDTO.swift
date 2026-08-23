import Foundation

/// The envelope `POST /api/v1/creature/register` expects.
///
/// Note the shape: `creature_config` is the creature's configuration JSON *as a string*, not
/// as a nested object. That's because this endpoint exists for controllers, which hold their
/// config as a file on disk and hand it over verbatim at startup. The universe assignment
/// lives in the server's runtime memory only; the config itself is upserted.
public struct RegisterCreatureRequestDTO: Encodable, Sendable {
    public let creatureConfig: String
    public let universe: UniverseIdentifier

    enum CodingKeys: String, CodingKey {
        case creatureConfig = "creature_config"
        case universe
    }

    public init(creatureConfig: String, universe: UniverseIdentifier) {
        self.creatureConfig = creatureConfig
        self.universe = universe
    }
}

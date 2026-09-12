import Foundation
import WorldCore

/// `/etc/creature/house.json`: where Home Assistant and Creature World are, which house this
/// is, and which entities become which world events. The token is never here — it comes from
/// `HA_TOKEN` in the environment (`/etc/default/creature-house`).
struct HouseConfiguration: Equatable, Sendable {
    static let defaultWorldURL = URL(string: "http://127.0.0.1:8001/world/v1")!
    static let defaultOutboxPath = "/var/lib/creature-house/outbox.jsonl"

    var homeAssistantURL: URL
    var worldURL: URL
    /// The house as a world entity (`house:aprils-nest`); its scenes and current scene live on it.
    var houseID: EntityID
    var mappings: [EntityMapping]
    /// Whether Home Assistant's scenes are offered to the world (and asks are acted on).
    var offersScenes: Bool
    var outboxPath: String

    static func load(from url: URL) throws -> HouseConfiguration {
        let raw = try JSONDecoder().decode(Raw.self, from: Data(contentsOf: url))
        guard let homeAssistantURL = URL(string: raw.homeAssistant.url),
            let scheme = homeAssistantURL.scheme, ["http", "https"].contains(scheme),
            homeAssistantURL.host != nil
        else {
            throw HouseConfigurationError.invalidURL("home_assistant.url", raw.homeAssistant.url)
        }
        let worldURL: URL
        if let rawWorld = raw.worldURL {
            guard let url = URL(string: rawWorld), url.scheme != nil, url.host != nil else {
                throw HouseConfigurationError.invalidURL("world_url", rawWorld)
            }
            worldURL = url
        } else {
            worldURL = defaultWorldURL
        }
        let mappings = try raw.mappings.map(EntityMapping.init(raw:))
        let entities = mappings.map(\.entityID)
        guard Set(entities).count == entities.count else {
            throw HouseConfigurationError.duplicateEntity
        }
        return HouseConfiguration(
            homeAssistantURL: homeAssistantURL,
            worldURL: worldURL,
            houseID: try EntityID(validating: raw.houseID ?? "house:home"),
            mappings: mappings,
            offersScenes: raw.scenes?.offer ?? true,
            outboxPath: raw.outboxPath ?? defaultOutboxPath
        )
    }

    private struct Raw: Decodable {
        struct HomeAssistant: Decodable { let url: String }
        struct Scenes: Decodable { let offer: Bool? }
        let homeAssistant: HomeAssistant
        let worldURL: String?
        let houseID: String?
        let mappings: [EntityMapping.Raw]
        let scenes: Scenes?
        let outboxPath: String?

        private enum CodingKeys: String, CodingKey {
            case homeAssistant = "home_assistant"
            case worldURL = "world_url"
            case houseID = "house_id"
            case mappings
            case scenes
            case outboxPath = "outbox_path"
        }
    }
}

/// One Home Assistant entity, and what it means to the world.
struct EntityMapping: Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        /// `lock.*`: `locked` / `unlocked` → `door.locked` / `door.unlocked`.
        case lock
        /// `binary_sensor.*` with a door class: `on` / `off` → `door.opened` / `door.closed`.
        case door
        /// `binary_sensor.*` motion: `on` / `off` → `motion.detected` / `motion.cleared`.
        case motion
        /// `person.*` or `device_tracker.*`: `home` → `person.arrived`, anything else → `person.left`.
        case person
        /// `sensor.*` with a number: → `environment.measurement_changed` with `predicate`.
        case measurement
        /// A camera's `*_person_detected` / `*_vehicle_detected` / `*_animal_detected`:
        /// `on` → `camera.<detects>_seen`; `off` is not news.
        case detection
    }

    enum Detects: String, Decodable, Sendable {
        case person, vehicle, animal
    }

    let entityID: String
    let subjectID: EntityID
    let kind: Kind
    /// For measurements: the world predicate (`temperature_f`).
    let predicate: String?
    /// For measurements: the least change worth an event; smaller moves are dropped.
    let minimumChange: Double
    /// For detections: what the camera saw.
    let detects: Detects?

    struct Raw: Decodable {
        let entityID: String
        let subjectID: String
        let kind: Kind
        let predicate: String?
        let minimumChange: Double?
        let detects: Detects?

        private enum CodingKeys: String, CodingKey {
            case entityID = "entity_id"
            case subjectID = "subject_id"
            case kind
            case predicate
            case minimumChange = "minimum_change"
            case detects
        }
    }

    init(
        entityID: String, subjectID: EntityID, kind: Kind, predicate: String? = nil,
        minimumChange: Double = 0, detects: Detects? = nil
    ) {
        self.entityID = entityID
        self.subjectID = subjectID
        self.kind = kind
        self.predicate = predicate
        self.minimumChange = minimumChange
        self.detects = detects
    }

    init(raw: Raw) throws {
        let entityID = raw.entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entityID.contains("."), !entityID.hasPrefix("."), !entityID.hasSuffix(".") else {
            throw HouseConfigurationError.invalidEntity(raw.entityID)
        }
        if raw.kind == .measurement {
            guard let predicate = raw.predicate?.trimmingCharacters(in: .whitespacesAndNewlines),
                !predicate.isEmpty
            else { throw HouseConfigurationError.measurementNeedsPredicate(entityID) }
        }
        if let change = raw.minimumChange, change < 0 || !change.isFinite {
            throw HouseConfigurationError.invalidMinimumChange(entityID)
        }
        if raw.kind == .detection, raw.detects == nil {
            throw HouseConfigurationError.detectionNeedsDetects(entityID)
        }
        self.init(
            entityID: entityID,
            subjectID: try EntityID(validating: raw.subjectID),
            kind: raw.kind,
            predicate: raw.predicate,
            minimumChange: raw.minimumChange ?? 0,
            detects: raw.detects
        )
    }
}

enum HouseConfigurationError: Error, LocalizedError, Equatable {
    case invalidURL(String, String)
    case invalidEntity(String)
    case duplicateEntity
    case measurementNeedsPredicate(String)
    case invalidMinimumChange(String)
    case detectionNeedsDetects(String)
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidURL(let key, let value): "\(key) is not an absolute http(s) URL: \(value)"
        case .invalidEntity(let entity): "not a Home Assistant entity id: \(entity)"
        case .duplicateEntity: "an entity is mapped twice"
        case .measurementNeedsPredicate(let entity):
            "measurement mapping \(entity) needs a predicate (temperature_f, humidity_percent, ...)"
        case .invalidMinimumChange(let entity):
            "minimum_change for \(entity) must be a non-negative number"
        case .detectionNeedsDetects(let entity):
            "detection mapping \(entity) needs `detects`: person, vehicle, or animal"
        case .missingToken:
            "HA_TOKEN is not set; put a Home Assistant long-lived access token in /etc/default/creature-house"
        }
    }
}

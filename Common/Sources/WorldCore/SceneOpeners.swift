import Foundation

/// When the world itself starts a scene: a person at the driveway, a door unlocking. The
/// rules live in `world.json` under `scenes.open_on`, the way the MQTT agent's areas and
/// cooldowns did, but as world rules — the house supplies the occasion, the birds the words.
public struct SceneOpeningRule: Hashable, Sendable, Codable {
    /// The world event type that opens a scene (`camera.person_seen`, `door.unlocked`).
    public var event: WorldEventType
    /// Only these places (the event's first subject); empty means any.
    public var places: [EntityID]
    /// The least time between two scenes for the same event and place.
    public var cooldownSeconds: TimeInterval

    public init(event: WorldEventType, places: [EntityID] = [], cooldownSeconds: TimeInterval = 300)
    {
        self.event = event
        self.places = places
        self.cooldownSeconds = cooldownSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case event, places
        case cooldownSeconds = "cooldown_seconds"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try WorldEventType(validating: container.decode(String.self, forKey: .event))
        places =
            try container.decodeIfPresent([String].self, forKey: .places)?
            .map(EntityID.init(validating:)) ?? []
        cooldownSeconds =
            try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownSeconds) ?? 300
        guard cooldownSeconds >= 0 else { throw WorldContractError.invalidScene }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event.rawValue, forKey: .event)
        try container.encode(places.map(\.rawValue), forKey: .places)
        try container.encode(cooldownSeconds, forKey: .cooldownSeconds)
    }
}

/// Decides, for an accepted event, whether the world should open a scene about it — pure but
/// for the cooldown memory.
public actor SceneOpeningPolicy {
    private let rules: [SceneOpeningRule]
    private var lastOpened: [String: Date] = [:]

    public init(rules: [SceneOpeningRule]) {
        self.rules = rules
    }

    /// The place the scene is about, when this event should open one now.
    public func shouldOpen(for event: WorldEventEnvelope, at now: Date) -> EntityID? {
        guard let place = event.subjectIDs.first else { return nil }
        guard
            let rule = rules.first(where: {
                $0.event == event.type && ($0.places.isEmpty || $0.places.contains(place))
            })
        else { return nil }
        let key = "\(event.type.rawValue)|\(place.rawValue)"
        if let last = lastOpened[key], now.timeIntervalSince(last) < rule.cooldownSeconds {
            return nil
        }
        lastOpened[key] = now
        return place
    }

    /// The stage note the birds read: "(A person was seen at the driveway.)"
    public static func triggerText(for event: WorldEventEnvelope, place: EntityID) -> String {
        let name = placeName(place)
        switch event.type {
        case HouseEvents.personSeen: return "A person was just seen at \(name)."
        case HouseEvents.vehicleSeen: return "A vehicle just arrived at \(name)."
        case HouseEvents.animalSeen: return "An animal was just seen at \(name)."
        case HouseEvents.doorUnlocked:
            return "\(name.prefix(1).uppercased() + name.dropFirst()) was just unlocked."
        case HouseEvents.doorLocked:
            return "\(name.prefix(1).uppercased() + name.dropFirst()) was just locked."
        case HouseEvents.doorOpened:
            return "\(name.prefix(1).uppercased() + name.dropFirst()) just opened."
        case HouseEvents.motionDetected: return "Something just moved in \(name)."
        case HouseEvents.personArrived:
            return
                "\(placeName(place).prefix(1).uppercased() + placeName(place).dropFirst()) just came home."
        case HouseEvents.personLeft:
            return
                "\(placeName(place).prefix(1).uppercased() + placeName(place).dropFirst()) just left."
        default:
            return "Something happened at \(name): \(event.type.rawValue)."
        }
    }

    /// `place:front-door` → "the front door"; `person:april` → "April".
    static func placeName(_ id: EntityID) -> String {
        let raw = id.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        let local = String(raw[raw.index(after: colon)...])
        let words = local.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if raw.hasPrefix("person:") { return words.map(\.capitalized).joined(separator: " ") }
        let name = words.joined(separator: " ")
        return ["outside", "outdoors"].contains(name) ? name : "the " + name
    }
}

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

/// When the house does not wake the birds. "Beaky isn't a security system, she's my familiar. I
/// have other alerts that go off at 3am." No exceptions: what the house sees at night is recorded
/// and is the morning's story, but nobody speaks. Wall-clock times in `time_zone`; a window that
/// crosses midnight (`23:00`–`07:00`) is the normal case.
public struct QuietHours: Hashable, Sendable, Codable {
    public var from: String
    public var to: String
    public var timeZone: String

    public init(from: String, to: String, timeZone: String = "America/Los_Angeles") {
        self.from = from
        self.to = to
        self.timeZone = timeZone
    }

    private enum CodingKeys: String, CodingKey {
        case from, to
        case timeZone = "time_zone"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(String.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)
        timeZone =
            try container.decodeIfPresent(String.self, forKey: .timeZone) ?? "America/Los_Angeles"
        guard Self.minutes(from) != nil, Self.minutes(to) != nil,
            TimeZone(identifier: timeZone) != nil
        else { throw WorldContractError.invalidScene }
    }

    /// Whether `date` falls inside the window.
    public func contains(_ date: Date) -> Bool {
        guard let start = Self.minutes(from), let end = Self.minutes(to),
            let zone = TimeZone(identifier: timeZone)
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return false }
        return start < end ? (now >= start && now < end) : (now >= start || now < end)
    }

    /// "23:00" → 1380; nil for anything else.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}

/// Decides, for an accepted event, whether the world should open a scene about it — pure but
/// for the cooldown memory.
public actor SceneOpeningPolicy {
    /// What the house does about an event: opens a scene the lead must speak in, or one the
    /// lead may decline.
    public struct Occasion: Hashable, Sendable {
        public var place: EntityID
        public var kind: SceneTrigger.Kind

        public init(place: EntityID, kind: SceneTrigger.Kind) {
            self.place = place
            self.kind = kind
        }
    }

    private let rules: [SceneOpeningRule]
    private let considerRules: [SceneOpeningRule]
    private let gapSeconds: TimeInterval
    private let quietHours: QuietHours?
    private var lastOpened: [String: Date] = [:]
    private var lastOpenedAny: Date?

    /// `gapSeconds`: the least time between any two scenes the house opens, whatever the rule;
    /// zero lets every rule speak. A walk to the carport opens four scenes — the front door,
    /// then its camera, then the driveway's, then the carport's — and April wants each of them:
    /// "I want to know that someone's out there sooner rather than later." The knob exists for
    /// a quieter house; the events a gap swallows become the story the next scene is told.
    public init(
        rules: [SceneOpeningRule], considerRules: [SceneOpeningRule] = [],
        gapSeconds: TimeInterval = 0, quietHours: QuietHours? = nil
    ) {
        self.rules = rules
        self.considerRules = considerRules
        self.gapSeconds = gapSeconds
        self.quietHours = quietHours
    }

    /// The place the scene is about, when this event should open one now.
    public func shouldOpen(for event: WorldEventEnvelope, at now: Date) -> EntityID? {
        occasion(for: event, at: now).map(\.place)
    }

    /// What the house does about this event now: a must-speak scene (`open_on`), a may-decline
    /// one (`consider_on`), or nothing. An `open_on` rule wins when both match.
    public func occasion(for event: WorldEventEnvelope, at now: Date) -> Occasion? {
        guard let place = event.subjectIDs.first else { return nil }
        // The birds sleep. Cooldowns are not touched: the first thing after seven may speak.
        if let quietHours, quietHours.contains(now) { return nil }
        // An ending is considered wherever its beginning is: a rule for `camera.vehicle_seen`
        // at the driveway also covers `camera.vehicle_gone` there, so the cleaners leaving is an
        // occasion without a line of configuration.
        let asSeen: WorldEventType? =
            switch event.type {
            case HouseEvents.personGone: HouseEvents.personSeen
            case HouseEvents.vehicleGone: HouseEvents.vehicleSeen
            default: nil
            }
        // A departure is always the house asking, with no line of configuration: the rule
        // that made it already decided April is home and the time is near.
        if event.type == HouseEvents.departureSoon || event.type == HouseEvents.departureNow
            || event.type == HouseEvents.reminderDue
        {
            let key =
                "\(SceneTrigger.Kind.houseConsideration.rawValue)|\(event.type.rawValue)|\(place.rawValue)"
            if let last = lastOpened[key], now.timeIntervalSince(last) < 300 { return nil }
            lastOpened[key] = now
            lastOpenedAny = now
            return Occasion(place: place, kind: .houseConsideration)
        }
        func matching(_ candidates: [SceneOpeningRule]) -> SceneOpeningRule? {
            candidates.first {
                ($0.event == event.type || $0.event == asSeen)
                    && ($0.places.isEmpty || $0.places.contains(place))
            }
        }
        let kind: SceneTrigger.Kind
        let rule: SceneOpeningRule
        if let must = matching(rules) {
            (rule, kind) = (must, .worldEvent)
        } else if let may = matching(considerRules) {
            (rule, kind) = (may, .houseConsideration)
        } else {
            return nil
        }
        let key = "\(kind.rawValue)|\(event.type.rawValue)|\(place.rawValue)"
        if let last = lastOpened[key], now.timeIntervalSince(last) < rule.cooldownSeconds {
            return nil
        }
        if gapSeconds > 0, let last = lastOpenedAny, now.timeIntervalSince(last) < gapSeconds {
            return nil
        }
        lastOpened[key] = now
        lastOpenedAny = now
        return Occasion(place: place, kind: kind)
    }

    /// " for two hours" / " for 25 minutes", from `after_seconds`; nothing when unknown.
    static func stay(_ event: WorldEventEnvelope) -> String {
        guard case .number(let seconds)? = event.payload["after_seconds"], seconds >= 60 else {
            return ""
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return " for \(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest < 10 { return " for \(hours == 1 ? "an hour" : "\(hours) hours")" }
        return " for \(hours == 1 ? "an hour" : "\(hours) hours") and \(rest) minutes"
    }

    /// The stage note the birds read: "(A person was seen at the driveway.)"
    public static func triggerText(for event: WorldEventEnvelope, place: EntityID) -> String {
        let name = placeName(place)
        switch event.type {
        case HouseEvents.personSeen: return "A person was just seen at \(name)."
        // "Seen", never "arrived": the camera cannot tell coming from going, and a trigger
        // that asserts a direction steers the mind before it has read the story.
        case HouseEvents.vehicleSeen: return "A vehicle was just seen at \(name)."
        case HouseEvents.animalSeen: return "An animal was just seen at \(name)."
        case HouseEvents.departureSoon, HouseEvents.departureNow:
            let value: String
            if case .string(let text)? = event.payload["value"] { value = text } else { value = "" }
            return event.type == HouseEvents.departureNow
                ? "It is time to leave: \(value). April is still home."
                : "Leaving soon: \(value). April is home."
        case HouseEvents.reminderDue:
            let value: String
            if case .string(let text)? = event.payload["value"] { value = text } else { value = "" }
            return "A reminder of April's is due: \(value). April is home."
        case HouseEvents.personGone:
            return "A person who had been at \(name)\(stay(event)) is no longer seen there."
        case HouseEvents.vehicleGone:
            return "A vehicle that had been at \(name)\(stay(event)) has gone."
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

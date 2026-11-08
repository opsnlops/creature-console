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

    /// Who speaks when the house opens a scene, in order: the lead, then the chorus shuffled
    /// each time. House scenes stop at three turns, and the order the minds had logged in in
    /// decided who was cut: after a restart Kenny was fourth all through the Bears game and
    /// never spoke, so the cast was shuffled (#274). But the first bird sets the scene, and with
    /// everyone shuffled that was usually a chorus bird on the smaller model. April: "they're
    /// talking about nonesense more... it needs to be Lead + random selection of chorus" (#278).
    /// Every bird present stays in the cast - the minds read who is in the room from it.
    public static func cast(
        _ present: [EntityID], lead: EntityID,
        using generator: inout some RandomNumberGenerator
    ) -> [EntityID] {
        let chorus = present.filter { $0 != lead }.shuffled(using: &generator)
        return present.contains(lead) ? [lead] + chorus : chorus
    }

    /// Whether this event reached the World as it happened, which is what makes it worth a
    /// scene: every stage note says something *just* happened. A house restarting restates the
    /// present, with Home Assistant's own time for when it became true - right for the facts,
    /// but "The front door was just locked" fifteen hours after it was (#279). Live events
    /// arrive within a second; judged by the event itself, not by when the opener reads it
    /// (#266). An event the World has not stamped yet has not arrived late.
    public static func isNews(_ event: WorldEventEnvelope, within seconds: TimeInterval) -> Bool {
        guard let received = event.receivedAt else { return true }
        // A game event held for the TV (#288) is as fresh as when it was released.
        var held: TimeInterval = 0
        if case .number(let value)? = event.payload["held_seconds"] { held = value }
        return received.timeIntervalSince(event.occurredAt) <= seconds + held
    }

    /// The place the scene is about, when this event should open one now; the scene is taken to
    /// open, and the cooldown is spent.
    public func shouldOpen(for event: WorldEventEnvelope, at now: Date) -> EntityID? {
        guard let occasion = occasion(for: event, at: now) else { return nil }
        opened(occasion, for: event, at: now)
        return occasion.place
    }

    /// What the house would do about this event now: a must-speak scene (`open_on`), a
    /// may-decline one (`consider_on`), or nothing. An `open_on` rule wins when both match.
    ///
    /// Nothing is spent until `opened`: an occasion that comes to nothing - a conversation
    /// already going, nobody in the room - leaves its cooldown for the next one. The Bears'
    /// touchdown came a millisecond after April started talking, was rightly held back, and
    /// spent the cooldown all the same; the extra point, thirty seconds later and after her
    /// scene had closed, then found it spent, and nobody was asked about either (#271).
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
            let occasion = Occasion(place: place, kind: .houseConsideration)
            if let last = lastOpened[Self.key(occasion, event)], now.timeIntervalSince(last) < 300 {
                return nil
            }
            return occasion
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
        let occasion = Occasion(place: place, kind: kind)
        if let last = lastOpened[Self.key(occasion, event)],
            now.timeIntervalSince(last) < rule.cooldownSeconds
        {
            return nil
        }
        if gapSeconds > 0, let last = lastOpenedAny, now.timeIntervalSince(last) < gapSeconds {
            return nil
        }
        return occasion
    }

    /// The scene for this occasion opened: its cooldown, and the house's gap, start now.
    public func opened(_ occasion: Occasion, for event: WorldEventEnvelope, at now: Date) {
        lastOpened[Self.key(occasion, event)] = now
        lastOpenedAny = now
    }

    private static func key(_ occasion: Occasion, _ event: WorldEventEnvelope) -> String {
        "\(occasion.kind.rawValue)|\(event.type.rawValue)|\(occasion.place.rawValue)"
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

    /// The stage note the birds read: "(A person was just seen at the driveway. April is home
    /// and lives alone, so it is most likely her.)" The house says who it most likely was - it
    /// knows whether April is home and whether anyone is expected - so the minds start from
    /// the right place; "most likely", because a camera sees a shape, and a certainty made
    /// the birds stop looking (the tree sprayer, the delivery driver: "They always assume
    /// it's me. They don't stop to think." - 2026-09-30, #214).
    public static func triggerText(
        for event: WorldEventEnvelope, place: EntityID, household: HouseholdSituation = .unknown
    ) -> String {
        let name = placeName(place)
        switch event.type {
        case HouseEvents.personSeen:
            return "A person was just seen at \(name)." + household.whoThatIs(seen: true)
        // "Seen", never "arrived": the camera cannot tell coming from going, and a trigger
        // that asserts a direction steers the mind before it has read the story.
        case HouseEvents.vehicleSeen:
            return "A vehicle was just seen at \(name)." + household.whereAprilIs
        case HouseEvents.animalSeen: return "An animal was just seen at \(name)."
        case HouseEvents.departureSoon, HouseEvents.departureNow:
            let value: String
            if case .string(let text)? = event.payload["value"] { value = text } else { value = "" }
            // The sky, when the world has it: "leave ten early, it's pouring".
            var weather = ""
            if case .string(let sky)? = event.payload["weather"], !sky.isEmpty {
                weather = " \(sky)"
            }
            return event.type == HouseEvents.departureNow
                ? "It is time to leave: \(value). April is still home.\(weather)"
                : "Leaving soon: \(value). April is home.\(weather)"
        case HouseEvents.reminderDue:
            let value: String
            if case .string(let text)? = event.payload["value"] { value = text } else { value = "" }
            return "A reminder of April's is due: \(value). April is home."
        case HouseEvents.gameScored, HouseEvents.gameScoreCorrected, HouseEvents.gamePossession,
            HouseEvents.gameFinal, HouseEvents.gameReviewed, HouseEvents.gamePenalty,
            HouseEvents.gameFirstDown, HouseEvents.gamePlay:
            let home: String =
                switch household.aprilHome {
                case true?: " April is home."
                case false?: " April is away."
                case nil: ""
                }
            return gameText(event) + home + gameFeeling(event)
        case HouseEvents.dusk, HouseEvents.dawn:
            var light = ""
            if case .number(let lux)? = event.payload["lux"] {
                light =
                    " The daylight outside is \(event.type == HouseEvents.dusk ? "down" : "up") to about \(Int(lux.rounded())) lux."
            }
            return
                (event.type == HouseEvents.dusk
                ? "Dusk is falling outside." : "Dawn is breaking outside.") + light
                + household.whereAprilIs
        case HouseEvents.personGone:
            return "A person who had been at \(name)\(stay(event)) is no longer seen there."
                + household.whoThatIs(seen: false)
        case HouseEvents.vehicleGone:
            return "A vehicle that had been at \(name)\(stay(event)) has gone."
                + household.whereAprilIs
        case HouseEvents.doorUnlocked:
            return "\(name.prefix(1).uppercased() + name.dropFirst()) was just unlocked."
        case HouseEvents.doorLocked:
            return "\(name.prefix(1).uppercased() + name.dropFirst()) was just locked."
        case HouseEvents.doorOpened:
            return "\(name.prefix(1).uppercased() + name.dropFirst()) just opened."
        case HouseEvents.motionDetected:
            return "Something just moved in \(name)." + household.whoThatIs(seen: true)
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

    /// "The Chicago Bears just scored against the Seattle Seahawks, the team April follows:
    /// Seattle Seahawks 7, Chicago Bears 14 (7:12 - 2nd). The play: ..." - or points coming off
    /// the board, a score taken back on review (#269), the ball changing hands, with where it is
    /// now, a first down, a flag, a review's ruling (#287), or the game over and who won.
    static func gameText(_ event: WorldEventEnvelope) -> String {
        func text(_ key: String) -> String? {
            switch event.payload[key] {
            case .string(let value)? where !value.isEmpty: value
            case .number(let value)?: String(Int(value))
            default: nil
            }
        }
        let team = text("team") ?? "April's team"
        let opponent = text("opponent") ?? "their opponent"
        // The final whistle (#276): who won, by how much, and nothing of the last play.
        if event.type == HouseEvents.gameFinal {
            let score = "\(text("team_score") ?? "0") to \(text("opponent_score") ?? "0")"
            let outcome =
                switch text("result") {
                case "won"?: "\(team) won, \(score)"
                case "lost"?: "\(team) lost, \(score)"
                case "tied"?: "it ended in a tie, \(score)"
                default: "it ended \(score)"
                }
            return
                "The game between \(team), the team April follows, and \(opponent) is over: \(outcome)."
        }
        let scorer = text("scored_by")
        let ruling =
            switch text("outcome") {
            case "reversed"?: ", and the call was reversed"
            case "upheld"?: ", and the call was upheld"
            case "stands"?: ", and the call on the field stands"
            default: ""
            }
        let game = "the game between \(team), the team April follows, and \(opponent)"
        var line =
            if event.type == HouseEvents.gamePlay {
                "The next play in \(game)"
            } else if event.type == HouseEvents.gameFirstDown {
                "\(text("possession") ?? "The side with the ball") just picked up a first down in \(game)"
            } else if event.type == HouseEvents.gamePenalty {
                "A flag in \(game): \(text("foul") ?? "a foul") on \(text("penalty_on") ?? "one side")"
                    + (text("yards").map { ", \($0) yards" } ?? "") + ". The score"
            } else if event.type == HouseEvents.gameReviewed {
                "A replay review just finished in \(game)"
                    + (text("challenged_by").map { " - \($0) challenged" }
                        ?? " - the booth's review")
                    + ruling + ". The score"
            } else if event.type == HouseEvents.gamePossession {
                "The ball just went to \(text("possession") ?? "the other side") in the game between \(team), the team April follows, and \(opponent)"
            } else if event.type == HouseEvents.gameScoreCorrected {
                "Points just came off the board in the game between \(team), the team April follows, and \(opponent) - a score taken back. It now stands"
            } else if scorer == team {
                "\(team), the team April follows, just scored against \(opponent)"
            } else if let scorer {
                "\(scorer) just scored against \(team), the team April follows"
            } else {
                "Both sides scored in the game between \(team), the team April follows, and \(opponent)"
            }
        line +=
            ": \(team) \(text("team_score") ?? "0"), \(opponent) \(text("opponent_score") ?? "0")"
        let when = [text("clock"), text("down_distance")].compactMap { $0 }
        if !when.isEmpty { line += " (\(when.joined(separator: "; ")))" }
        line += "."
        if let play = text("last_play") {
            line += " The play: \(play)" + (play.hasSuffix(".") ? "" : ".")
        }
        return line
    }

    /// How to watch it (#287): April, watching with the birds, "Can you ask them to be really
    /// emotional, too? It's fun when they get super happy on good plays." A fan's invitation,
    /// each bird in its own way; whether this play deserves it is still theirs to judge.
    static func gameFeeling(_ event: WorldEventEnvelope) -> String {
        let team: String =
            if case .string(let name)? = event.payload["team"], !name.isEmpty { name } else {
                "April's team"
            }
        return
            " You are watching with April as fans of \(team): feel it out loud, each in your own way - overjoyed at a good play for \(team), crushed or indignant at a bad one."
    }

    /// `place:front-door` → "the front door"; `person:april` → "April".
    public static func placeName(_ id: EntityID) -> String {
        let raw = id.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        let local = String(raw[raw.index(after: colon)...])
        let words = local.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if raw.hasPrefix("person:") { return words.map(\.capitalized).joined(separator: " ") }
        let name = words.joined(separator: " ")
        return ["outside", "outdoors"].contains(name) ? name : "the " + name
    }
}

/// What the house knows about who is about, at the moment a camera sees someone: whether
/// April is home, and whether a visitor or a delivery is expected. April lives alone, so when
/// she is home and nobody is expected, a person on any camera is most likely her, and the
/// stage note says so - a starting point for the minds, not the end of their thinking.
public struct HouseholdSituation: Sendable, Equatable {
    /// Whether April is home, as the presence sensor has it; nil when the house cannot say.
    public var aprilHome: Bool?
    /// The house's `visitor.expected`, if anyone is: "Tamara for cleaning, Wednesday".
    public var visitorExpected: String?
    /// An order on its way today, if any: "Amazon: Hardware". The driver is a stranger at the
    /// door April did not invite, and just as expected.
    public var deliveryExpected: String?

    public init(aprilHome: Bool?, visitorExpected: String? = nil, deliveryExpected: String? = nil) {
        self.aprilHome = aprilHome
        self.visitorExpected = visitorExpected
        self.deliveryExpected = deliveryExpected
    }

    public static let unknown = HouseholdSituation(aprilHome: nil)

    /// Nobody but April could be about.
    public var nobodyExpected: Bool { visitorExpected == nil && deliveryExpected == nil }

    /// "a visitor is expected - Tamara - and a delivery - Amazon: Hardware"; nil when nobody is.
    private var expectedWords: String? {
        switch (visitorExpected, deliveryExpected) {
        case (let visitor?, let delivery?):
            return "a visitor is expected - \(visitor) - and a delivery - \(delivery) -"
        case (let visitor?, nil): return "a visitor is expected - \(visitor) -"
        case (nil, let delivery?): return "a delivery is expected - \(delivery) -"
        case (nil, nil): return nil
        }
    }

    /// Who else a person could be: "them", "the driver", or both.
    private var others: String {
        switch (visitorExpected != nil, deliveryExpected != nil) {
        case (true, true): return "them or the driver"
        case (false, true): return "the driver"
        default: return "them"
        }
    }

    /// Who a person at home could be: "either her or the driver", "her, them, or the driver".
    private var herOrOthers: String {
        visitorExpected != nil && deliveryExpected != nil
            ? "her, them, or the driver" : "either her or \(others)"
    }

    /// " April is home and lives alone, so it is most likely her." - the clause after a person is seen
    /// (`seen`) or no longer seen; nothing when the house does not know where she is.
    func whoThatIs(seen: Bool) -> String {
        let pronoun = seen ? "it is" : "it was"
        switch aprilHome {
        case true?:
            if let expectedWords {
                return " April is home, and \(expectedWords) so \(pronoun) \(herOrOthers)."
            }
            return " April is home and lives alone, so \(pronoun) most likely her."
        case false?:
            if let expectedWords {
                return " April is away; \(expectedWords) so \(pronoun) probably \(others)."
            }
            return " April is away, so \(pronoun) somebody else."
        case nil:
            return ""
        }
    }

    /// " April is home." - beside a vehicle, which could be hers or a delivery's.
    var whereAprilIs: String {
        let expected = [
            visitorExpected.map { "a visitor is expected - \($0)" },
            deliveryExpected.map { "a delivery is expected - \($0)" },
        ].compactMap { $0 }.map { "; \($0)" }.joined()
        switch aprilHome {
        case true?: return " April is home\(expected)."
        case false?: return " April is away\(expected)."
        case nil: return ""
        }
    }
}

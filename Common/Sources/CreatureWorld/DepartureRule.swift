import Foundation
import WorldCore

/// `departures` in world.json: how long before an away event April should leave, by the words
/// in its location, and how much notice she wants.
struct DepartureRuleConfiguration: Codable, Equatable, Sendable {
    struct Travel: Codable, Equatable, Sendable {
        /// Any of these in the event's location (case-insensitive) means this travel time.
        var words: [String]
        var minutes: Int
    }

    /// How long before leave-by the birds first say something.
    var headsUpMinutes: Int = 20
    /// Travel time when no words match.
    var defaultTravelMinutes: Int = 30
    var travel: [Travel] = []
    /// Departures are only worth a word for events this far ahead.
    var horizonHours: Int = 18
    /// Where the sky's facts are - the Bridge casts the forecast on `place:outside` - so a
    /// departure carries the weather: "leave ten early, it's pouring".
    var outside: String = "place:outside"

    init(
        headsUpMinutes: Int = 20, defaultTravelMinutes: Int = 30, travel: [Travel] = [],
        horizonHours: Int = 18, outside: String = "place:outside"
    ) {
        self.headsUpMinutes = headsUpMinutes
        self.defaultTravelMinutes = defaultTravelMinutes
        self.travel = travel
        self.horizonHours = horizonHours
        self.outside = outside
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headsUpMinutes = try container.decodeIfPresent(Int.self, forKey: .headsUpMinutes) ?? 20
        defaultTravelMinutes =
            try container.decodeIfPresent(Int.self, forKey: .defaultTravelMinutes) ?? 30
        travel = try container.decodeIfPresent([Travel].self, forKey: .travel) ?? []
        horizonHours = try container.decodeIfPresent(Int.self, forKey: .horizonHours) ?? 18
        outside = try container.decodeIfPresent(String.self, forKey: .outside) ?? "place:outside"
    }

    private enum CodingKeys: String, CodingKey {
        case headsUpMinutes = "heads_up_minutes"
        case defaultTravelMinutes = "default_travel_minutes"
        case travel
        case horizonHours = "horizon_hours"
        case outside
    }

    /// Minutes of travel to a location, by its words.
    func travelMinutes(to location: String?) -> Int {
        let lower = (location ?? "").lowercased()
        for rule in travel where rule.words.contains(where: { lower.contains($0.lowercased()) }) {
            return rule.minutes
        }
        return defaultTravelMinutes
    }
}

/// The plan's Phase 6, as a world rule: an away event on the calendar has a leave-by time -
/// its start less the travel to its location - and when that time draws near and April is
/// still home, the house has something to say. The birds get the occasion and the facts
/// ("leaving by 3:25 makes it"); what they say, and whether, is theirs. Once at the heads-up,
/// once more at leave-by itself if she is still here, and then it lets her be.
actor DepartureRule {
    static let sourceID = try! SourceID(validating: "world:departures")
    static let factPredicate = "departure.due"

    struct Departure: Equatable, Sendable {
        var event: EntityID
        var title: String
        var location: String
        var startsAt: Date
        var leaveBy: Date
        var value: String
    }

    let configuration: DepartureRuleConfiguration
    let atHome: [String]
    let house: EntityID
    let zone: TimeZone
    private let facts: FactRepository
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void
    /// What has been said for each event, so each word is said once.
    private var said: [EntityID: Set<String>] = [:]
    /// The facts cast, by event, to take back when the event moves or goes.
    private var cast: [EntityID: Departure] = [:]

    init(
        configuration: DepartureRuleConfiguration, atHome: [String], house: EntityID,
        zone: TimeZone, facts: FactRepository,
        accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.configuration = configuration
        self.atHome = atHome.map { $0.lowercased() }
        self.house = house
        self.zone = zone
        self.facts = facts
        self.accept = accept
    }

    /// One pass. Returns the departures in force (their facts on the house).
    @discardableResult
    func sweep(now: Date) async throws -> [EntityID: Departure] {
        let starts = try await facts.currentFacts(
            about: [], predicate: "calendar.starts_at", limit: 500, at: now)
        let horizon = now.addingTimeInterval(TimeInterval(configuration.horizonHours) * 3_600)
        var wanted: [EntityID: Departure] = [:]
        for start in starts {
            guard case .string(let raw) = start.value, let startsAt = WorldJSON.date(from: raw),
                startsAt > now, startsAt <= horizon
            else { continue }
            let event = try await facts.currentFacts(subjectID: start.subjectID, at: now)
            let text = { (predicate: String) -> String? in
                if case .string(let value)? = event.first(where: { $0.predicate == predicate })?
                    .value
                {
                    return value
                }
                return nil
            }
            let location = text("calendar.location") ?? ""
            // At the house, or an all-day marker, is nowhere to go.
            guard !isAtHome(location), text("calendar.all_day") == nil,
                event.first(where: { $0.predicate == "calendar.all_day" })?.value != .bool(true)
            else { continue }
            let travel = TimeInterval(configuration.travelMinutes(to: location)) * 60
            let leaveBy = startsAt.addingTimeInterval(-travel)
            let title = text("calendar.title") ?? "an appointment"
            let where_ = Self.placeWords(location)
            let value =
                "\(title)\(where_.isEmpty ? "" : " in \(where_)") at \(Self.clock(startsAt, zone: zone)); leaving by \(Self.clock(leaveBy, zone: zone)) makes it"
            wanted[start.subjectID] = Departure(
                event: start.subjectID, title: title, location: location, startsAt: startsAt,
                leaveBy: leaveBy, value: value)
        }
        // The facts: on the house, until the event starts.
        for (event, departure) in wanted where cast[event] != departure {
            try await accept(
                try given(
                    .string(departure.value), validUntil: departure.startsAt,
                    itemID: "departure:\(event.rawValue):\(WorldJSON.timestamp(departure.leaveBy))",
                    now: now))
            cast[event] = departure
        }
        for (event, _) in cast where wanted[event] == nil {
            try await accept(
                try given(
                    .null, validUntil: now.addingTimeInterval(1),
                    itemID: "departure:\(event.rawValue):gone:\(WorldJSON.timestamp(now))", now: now
                ))
            cast[event] = nil
            said[event] = nil
        }
        // The words: the heads-up, then leave-by itself - each once, and only while April is
        // home to hear them. Away already, there is nothing to say.
        let headsUp = TimeInterval(configuration.headsUpMinutes) * 60
        for (event, departure) in wanted {
            let stage: String?
            if now >= departure.leaveBy {
                stage = "now"
            } else if now >= departure.leaveBy.addingTimeInterval(-headsUp) {
                stage = "soon"
            } else {
                stage = nil
            }
            guard let stage, !(said[event]?.contains(stage) ?? false) else { continue }
            said[event, default: []].insert(stage)
            guard try await aprilIsHome(now: now) else { continue }
            try await accept(try await occasion(departure, stage: stage, now: now))
        }
        return wanted
    }

    private func aprilIsHome(now: Date) async throws -> Bool {
        let april = try EntityID(validating: "person:april")
        let state = try await facts.currentFacts(subjectID: april, at: now)
            .first { $0.predicate == WorldFacts.personState }
        guard case .string(let value)? = state?.value else { return false }
        return value == PersonPresenceState.home.rawValue
    }

    private func isAtHome(_ location: String) -> Bool {
        let lower = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return true }
        return atHome.contains { lower.contains($0) }
    }

    /// "5522 Freeland Avenue, Freeland, Washington 98249" → "Freeland": the town, when the
    /// location is an address; else the location itself, shortened.
    static func placeWords(_ location: String) -> String {
        let parts = location.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count >= 2 {
            // The second part of a US address is the city.
            let city = parts[1].split(separator: " ").filter { Int($0) == nil }.joined(
                separator: " ")
            if !city.isEmpty { return city }
        }
        return String(location.prefix(40))
    }

    static func clock(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func given(_ value: WorldJSONValue, validUntil: Date, itemID: String, now: Date)
        throws -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType,
            occurredAt: now,
            source: EventSource(id: Self.sourceID, kind: "world", sourceEventID: itemID),
            subjectIDs: [house],
            epistemic: EpistemicState(type: .scheduled, confidence: 1),
            payload: [
                "subject_id": .string(house.rawValue),
                "predicate": .string(Self.factPredicate),
                "value": value,
                "valid_to": .string(WorldJSON.timestamp(validUntil)),
            ])
    }

    /// The occasion the house gives the birds: `departure.soon` at the heads-up,
    /// `departure.now` at leave-by. The scene openers make it a house consideration.
    private func occasion(_ departure: Departure, stage: String, now: Date) async throws
        -> WorldEventEnvelope
    {
        var payload: [String: WorldJSONValue] = [
            "event_id": .string(departure.event.rawValue),
            "title": .string(departure.title),
            "location": .string(departure.location),
            "starts_at": .string(WorldJSON.timestamp(departure.startsAt)),
            "leave_by": .string(WorldJSON.timestamp(departure.leaveBy)),
            "value": .string(departure.value),
        ]
        if let weather = try await weather(now: now) {
            payload["weather"] = .string(weather)
        }
        return try WorldEventEnvelope(
            type: stage == "now" ? HouseEvents.departureNow : HouseEvents.departureSoon,
            occurredAt: now,
            source: EventSource(
                id: Self.sourceID, kind: "world",
                sourceEventID:
                    "departure:\(departure.event.rawValue):\(stage):\(WorldJSON.timestamp(departure.leaveBy))"
            ),
            subjectIDs: [house, departure.event],
            placeID: house,
            epistemic: EpistemicState(type: .scheduled, confidence: 1),
            payload: payload)
    }

    /// The sky as April steps out: today's forecast and when rain is next likely, from the
    /// Bridge's facts on the outside. Nil when the world has no forecast.
    private func weather(now: Date) async throws -> String? {
        guard let outside = EntityID(rawValue: configuration.outside) else { return nil }
        let sky = try await facts.currentFacts(subjectID: outside, at: now)
        var parts: [String] = []
        if case .string(let today)? = sky.first(where: { $0.predicate == "forecast.today" })?.value
        {
            parts.append("Today: \(today).")
        }
        if case .string(let rain)? = sky.first(where: { $0.predicate == "forecast.next_rain" })?
            .value
        {
            parts.append("Rain: \(rain).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static let meanings: [String: String] = [
        factPredicate:
            "somewhere April has to be, away from the house, and when she should leave to make it - from her calendar and the travel time to the place"
    ]
}

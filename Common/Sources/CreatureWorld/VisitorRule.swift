import Foundation
import WorldCore

/// `calendar` in world.json: which locations mean the house. An event with no location is at
/// the house; one whose location contains any of these words is too.
struct CalendarRuleConfiguration: Codable, Equatable, Sendable {
    var atHome: [String] = ["home", "house"]

    init(atHome: [String] = ["home", "house"]) {
        self.atHome = atHome
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        atHome = try container.decodeIfPresent([String].self, forKey: .atHome) ?? ["home", "house"]
    }

    private enum CodingKeys: String, CodingKey {
        case atHome = "at_home"
    }
}

/// The world's own rule for the calendar: an event at the house, with a person April knows,
/// starting within a day, is a visitor expected - the same `visitor.expected` fact April casts
/// by telling Beaky "Jesse's coming Thursday", so nothing downstream changes. Deterministic and
/// testable; the Bridge only says what the calendar says, and the mind only judges.
actor VisitorRule {
    static let sourceID = try! SourceID(validating: "world:calendar")
    static let horizon: TimeInterval = 24 * 3_600
    static let lingerAfterEnd: TimeInterval = 2 * 3_600

    /// Words that make a location the house: empty, or containing one of these.
    let atHome: [String]
    private let facts: FactRepository
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void
    /// The visitor facts this rule cast, by event entity, so a cancelled or moved event's
    /// visitor is taken back rather than left standing.
    private var cast: [EntityID: Visitor] = [:]

    struct Visitor: Equatable, Sendable {
        var person: EntityID
        var value: String
        var until: Date
    }

    init(
        atHome: [String], facts: FactRepository,
        accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.atHome = atHome.map { $0.lowercased() }
        self.facts = facts
        self.accept = accept
    }

    /// One pass: cast the visitors the calendar now implies, take back the ones it no longer
    /// does. Returns the visitors in force.
    @discardableResult
    func sweep(now: Date) async throws -> [EntityID: Visitor] {
        let starts = try await facts.currentFacts(
            about: [], predicate: "calendar.starts_at", limit: 500, at: now)
        var wanted: [EntityID: Visitor] = [:]
        for start in starts {
            guard case .string(let raw) = start.value, let startsAt = WorldJSON.date(from: raw),
                startsAt <= now.addingTimeInterval(Self.horizon)
            else { continue }
            let event = try await facts.currentFacts(subjectID: start.subjectID, at: now)
            let value = { (predicate: String) -> String? in
                if case .string(let text)? = event.first(where: { $0.predicate == predicate })?
                    .value
                {
                    return text
                }
                return nil
            }
            guard let with = value("calendar.with").flatMap(EntityID.init(rawValue:)),
                with.rawValue.hasPrefix("person:")
            else { continue }
            let endsAt = value("calendar.ends_at").flatMap(WorldJSON.date(from:)) ?? startsAt
            let until = endsAt.addingTimeInterval(Self.lingerAfterEnd)
            guard until > now, isAtHome(value("calendar.location")) else { continue }
            let when = value("calendar.when") ?? WorldJSON.timestamp(startsAt)
            let title = value("calendar.title") ?? ""
            wanted[start.subjectID] = Visitor(
                person: with, value: title.isEmpty ? when : "\(when), \(title)", until: until)
        }
        for (event, visitor) in wanted where cast[event] != visitor {
            try await accept(
                try given(
                    visitor.person, .string(visitor.value), validUntil: visitor.until,
                    itemID: "visitor:\(event.rawValue):\(visitor.value)", now: now))
            cast[event] = visitor
        }
        for (event, visitor) in cast where wanted[event] == nil {
            try await accept(
                try given(
                    visitor.person, .null, validUntil: now.addingTimeInterval(1),
                    itemID: "visitor:\(event.rawValue):gone:\(WorldJSON.timestamp(now))", now: now))
            cast[event] = nil
        }
        return wanted
    }

    private func isAtHome(_ location: String?) -> Bool {
        guard let location = location?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !location.isEmpty
        else { return true }
        return atHome.contains { location.contains($0) }
    }

    private func given(
        _ person: EntityID, _ value: WorldJSONValue, validUntil: Date, itemID: String, now: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType,
            occurredAt: now,
            source: EventSource(id: Self.sourceID, kind: "world", sourceEventID: itemID),
            subjectIDs: [person],
            epistemic: EpistemicState(type: .scheduled, confidence: 1),
            payload: [
                "subject_id": .string(person.rawValue),
                "predicate": .string(WorldFacts.visitorExpected),
                "value": value,
                "valid_to": .string(WorldJSON.timestamp(validUntil)),
            ])
    }
}

import Foundation
import WorldCore

/// The world's clock for the nightly memory: one timer for the next consolidation, whose firing
/// is the event a mind with a memory model acts on. Rescheduled after every firing; a timer id
/// per day makes scheduling idempotent across restarts.
enum MemoryClock {
    static let eventType = WorldEventType(rawValue: "memory.consolidate")!

    static func schedule(
        after now: Date, memory: MemoryConfiguration,
        using schedule: (WorldTimer) async throws -> Void
    ) async throws {
        let next = memory.nextRun(after: now)
        try await schedule(
            WorldTimer(
                timerID: try TimerID(validating: "timer:memory-consolidate:\(next.day)"),
                purpose: eventType,
                dueAt: next.dueAt,
                status: .pending,
                subjectIDs: [],
                causedBy: [],
                payload: [
                    "day": .string(next.day),
                    "time_zone": .string(memory.timeZone),
                ]
            ))
    }

    static let requestSourceID = try! SourceID(validating: "world:memory")

    /// "Remember this day" asked for by hand (`POST /v1/days/{day}/remember`): the same event
    /// the timer would have produced, so the mind cannot tell the two apart. Every request is
    /// its own event; asking twice remembers twice.
    static func request(day: String, memory: MemoryConfiguration, now: Date) throws
        -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: eventType,
            occurredAt: now,
            source: EventSource(
                id: requestSourceID, kind: "world",
                sourceEventID: "remember:\(day):\(WorldJSON.timestamp(now))"),
            subjectIDs: [],
            epistemic: EpistemicState(type: .scheduled, confidence: 1),
            payload: [
                "day": .string(day),
                "time_zone": .string(memory.timeZone),
                "requested_by": .string("api"),
            ]
        )
    }
}

/// One day of the world, assembled for the memory job: happenings, the house conversation, the
/// scenes' lines, and what was cast that day.
struct DayDigestBuilder {
    let persistence: MongoWorldPersistence
    let houseConversation: ConversationID
    let memory: MemoryConfiguration

    func digest(of day: String) async throws -> DayDigest? {
        guard let bounds = MemoryConfiguration.bounds(ofDay: day, in: memory.zone) else {
            return nil
        }
        let events = try await persistence.events.allEvents(from: bounds.from, to: bounds.to)
        // What the house saw. A cast fact is not among them: `learned` carries each one once,
        // with who said it - the happenings had all 951 of 2026-10-16's again, 287 of them the
        // Bridge's heartbeat and 238 the night's own memory writes, each rendered "facts.given
        // at the carport" (#242).
        let happenings = events.filter {
            Happening.isStoryworthy($0) && $0.type != GivenFactAnnouncement.eventType
        }.map { event in
            let subject =
                event.subjectIDs.first { !$0.rawValue.hasPrefix("character:") }
                ?? event.subjectIDs.first ?? event.placeID ?? houseConversationEntity
            return Happening(
                occurredAt: event.occurredAt, type: event.type, subjectID: subject,
                summary: PresentWorldKnowledge.summary(of: event, subject: subject))
        }
        // What the world was told that a memory could be about: never a body's readings (four
        // thousand a day, 370k tokens of a night's prompt) and never a heartbeat.
        let distant = Self.distantCalendarEntries(in: events, after: bounds.to)
        // And nothing the world keeps to itself - a taught place's point, a contact's number,
        // the calendar's raw times: the record is the minds' view of the day, read by the night's
        // memory and by a bird asking `query_day` (#244).
        let hidden = try await persistence.factKinds.hiddenFromMinds()
        let learned = Self.lastOfFolded(events.filter { Self.isMemorable($0) }).compactMap {
            event -> DayDigest.Line? in
            guard case .string(let subject)? = event.payload["subject_id"],
                case .string(let predicate)? = event.payload["predicate"],
                !distant.contains(subject), !hidden.contains(predicate)
            else { return nil }
            // Marked when it was learned in a whisper: a mind is handed `heard(by:)` (#263).
            return DayDigest.Line(
                at: event.occurredAt, who: event.source.id.rawValue,
                text: "\(subject) \(predicate) = \(Self.rendered(event.payload["value"]))",
                aloneWith: GivenFactAnnouncement.aloneWith(in: event))
        }
        let items = try await persistence.conversations.conversationItems(
            in: houseConversation, from: bounds.from, to: bounds.to, limit: 2_000)
        // Whole, each whisper marked with its bird: a mind is handed `heard(by:)` (#261).
        let conversation = items.map {
            DayDigest.Line(
                at: $0.createdAt, who: $0.authorID.rawValue, text: $0.text,
                aloneWith: $0.aloneWith)
        }
        let scenes = try await persistence.scenes.scenes(
            from: bounds.from, to: bounds.to, limit: 500)
        let sceneLines = scenes.filter { !$0.spokenTurns.isEmpty }.map { scene in
            DayDigest.SceneLines(
                openedAt: scene.openedAt, trigger: scene.trigger.text,
                lines: scene.spokenTurns.map {
                    DayDigest.Line(
                        at: $0.answeredAt, who: $0.characterID.rawValue, text: $0.text ?? "")
                })
        }
        return DayDigest(
            day: day, timeZone: memory.timeZone, happenings: happenings,
            conversation: conversation, scenes: sceneLines, learned: learned)
    }

    private var houseConversationEntity: EntityID {
        (try? EntityID(validating: "house:aprils-nest")) ?? EntityID(rawValue: "house:aprils-nest")!
    }

    /// Facts a source casts to say it is alive, every few minutes: state, never a memory.
    static let heartbeatPredicates: Set<String> = ["bridge.online"]

    /// A given fact worth a line in the day's record: not telemetry, not a heartbeat, and not a
    /// memory - the minds' own memories of the day before, written at 3:30, were 488 of
    /// 2026-10-16's 664 lines (#242).
    static func isMemorable(_ event: WorldEventEnvelope) -> Bool {
        guard event.type == GivenFactAnnouncement.eventType,
            !Happening.telemetrySourceKinds.contains(event.source.kind),
            case .string(let predicate)? = event.payload["predicate"]
        else { return false }
        return !heartbeatPredicates.contains(predicate)
            && WorldFacts.memoryFamily(of: predicate) == nil
    }

    /// The folded families - the forecast, the sensors - restate the same thing all day:
    /// `forecast.next_rain` was cast 19 times on 2026-10-16. Only each subject's and
    /// predicate's last value from a source stays; what minds and people said is kept every
    /// time it changed (#242).
    static func lastOfFolded(_ events: [WorldEventEnvelope]) -> [WorldEventEnvelope] {
        func key(_ event: WorldEventEnvelope) -> String? {
            guard case .string(let subject)? = event.payload["subject_id"],
                case .string(let predicate)? = event.payload["predicate"],
                WorldKnowledgeLimits.foldedPrefixes.contains(where: { predicate.hasPrefix($0) })
            else { return nil }
            return "\(event.source.id.rawValue)|\(subject)|\(predicate)"
        }
        var last: [String: Int] = [:]
        for (index, event) in events.enumerated() {
            if let key = key(event) { last[key] = index }
        }
        return events.enumerated().compactMap { index, event in
            guard let key = key(event) else { return event }
            return last[key] == index ? event : nil
        }
    }

    /// How far past the day a calendar entry cast that day is still news about it.
    static let calendarHorizon: TimeInterval = 14 * 86_400

    /// Calendar entries cast this day that start well after it. The Bridge's calendar reaches
    /// a year ahead, a day further each day, so every recurring event gains its far-off
    /// instance daily: on 2026-09-27 the only Flight School in the record was September 27,
    /// 2027, and the memory "corrected" the birds' right answer - tomorrow at four (#208).
    static func distantCalendarEntries(in events: [WorldEventEnvelope], after end: Date)
        -> Set<String>
    {
        var distant: Set<String> = []
        for event in events where event.type == GivenFactAnnouncement.eventType {
            guard case .string(let subject)? = event.payload["subject_id"],
                subject.hasPrefix("event:"),
                event.payload["predicate"] == .string(WorldFacts.calendarStartsAt),
                case .string(let text)? = event.payload["value"],
                let starts = WorldJSON.date(from: text),
                starts > end.addingTimeInterval(calendarHorizon)
            else { continue }
            distant.insert(subject)
        }
        return distant
    }

    /// A value as the record shows it: text as itself, nothing as "(retracted)", anything
    /// else as JSON - not Swift's description of the enum, which spelled a counter object
    /// out as `object(["websocket_messages_sent": WorldCore.WorldJSONValue.number(…`.
    static func rendered(_ value: WorldJSONValue?) -> String {
        switch value {
        case .string(let text)?: return text
        case .null?, nil: return "(retracted)"
        case .some(let other):
            guard let data = try? WorldJSON.makeEncoder().encode(other) else { return "?" }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

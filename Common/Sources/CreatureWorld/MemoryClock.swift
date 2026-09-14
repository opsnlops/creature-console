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
        let events = try await persistence.events.events(
            from: bounds.from, to: bounds.to, limit: 5_000)
        let happenings = events.filter { Happening.isStoryworthy($0.type) }.map { event in
            let subject =
                event.subjectIDs.first { !$0.rawValue.hasPrefix("character:") }
                ?? event.subjectIDs.first ?? event.placeID ?? houseConversationEntity
            return Happening(
                occurredAt: event.occurredAt, type: event.type, subjectID: subject,
                summary: PresentWorldKnowledge.summary(of: event, subject: subject))
        }
        let learned = events.filter { $0.type == GivenFactAnnouncement.eventType }.compactMap {
            event -> DayDigest.Line? in
            guard case .string(let subject)? = event.payload["subject_id"],
                case .string(let predicate)? = event.payload["predicate"]
            else { return nil }
            let value: String =
                switch event.payload["value"] {
                case .string(let text)?: text
                case .null?, nil: "(retracted)"
                case .some(let other): String(describing: other)
                }
            return DayDigest.Line(
                at: event.occurredAt, who: event.source.id.rawValue,
                text: "\(subject) \(predicate) = \(value)")
        }
        let items = try await persistence.conversations.conversationItems(
            in: houseConversation, from: bounds.from, to: bounds.to, limit: 2_000)
        let conversation = items.map {
            DayDigest.Line(at: $0.createdAt, who: $0.authorID.rawValue, text: $0.text)
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
}

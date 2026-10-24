import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// Recent events are the newest ones (#265): an entity's page was the week's oldest fifty, and
/// a story past 96 events in its fifteen minutes would have lost the newest.
@Suite(
    "Recent events, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct RecentEventsMongoTests {
    // Now, in whole seconds: events expire by kind, and an old one can be swept mid-test.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    private func motion(at place: EntityID, _ date: Date) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: HouseEvents.motionDetected, occurredAt: date,
            source: EventSource(
                id: try SourceID(validating: "home-assistant:recent-tests"),
                kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
            subjectIDs: [place], placeID: place,
            epistemic: EpistemicState(type: .observed, confidence: 1), payload: [:])
    }

    @Test("The newest events since a moment, oldest first, and the story keeps the newest")
    func newestEventsSince() async throws {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "recent-events-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let place = try EntityID(validating: "place:hall-\(UUID().uuidString.lowercased())")
        // A busy hall: 120 sightings over ten minutes, more than the story reads (12 × 8).
        let start = now.addingTimeInterval(-600)
        var appended: [WorldEventEnvelope] = []
        for index in 0..<120 {
            let event = try motion(at: place, start.addingTimeInterval(Double(index) * 5))
            _ = try await persistence.events.append(event, receivedAt: event.occurredAt)
            appended.append(event)
        }

        let recent = try await persistence.events.events(
            about: [place], since: now.addingTimeInterval(-86_400), limit: 50)
        #expect(recent.map(\.eventID) == appended.suffix(50).map(\.eventID))

        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        let story = try await knowledge.recentHappenings(
            about: [place], since: now.addingTimeInterval(-WorldKnowledgeLimits.happeningsWindow),
            limit: WorldKnowledgeLimits.maximumHappenings)
        #expect(story.count == WorldKnowledgeLimits.maximumHappenings)
        #expect(story.last?.occurredAt == appended.last?.occurredAt)
    }
}

import Foundation
import Testing
import WorldCore

@testable import creature_world

@Suite("The world's first facts")
struct PresenceReducerTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let mango = try! EntityID(validating: "character:mango")
    private let home = try! EntityID(validating: "region:home")
    private let april = try! EntityID(validating: "person:april")

    @Test("A login becomes a presence fact for the character; a logout clears it")
    func loginAndLogoutBecomeFacts() throws {
        let reducer = CharacterPresenceReducer()
        let login = try sessionEvent(CharacterSessionService.loginEventType)
        let logout = try sessionEvent(CharacterSessionService.logoutEventType)

        let arrived = try reducer.reduce(login).changedFacts
        let left = try reducer.reduce(logout).changedFacts

        let fact = try #require(arrived.first)
        #expect(fact.subjectID == mango)
        #expect(fact.predicate == PresenceFacts.characterRegion)
        #expect(fact.value == .string("region:home"))
        #expect(fact.epistemic.type == .observed)
        #expect(fact.derivedFrom == [.event(login.eventID)])
        #expect(left.first?.value == .null)
        #expect(try reducer.reduce(try unrelatedEvent()).changedFacts.isEmpty)
    }

    @Test("A configured assumption is announced once and becomes an assumed fact")
    func assumptionBecomesAFact() throws {
        let configuration = PresenceConfiguration(
            assumed: [
                april: try PresenceConfiguration.AssumedPresence(
                    state: .home, physicallyAudible: true, confidence: 0.9)
            ])
        let events = try AssumedPresenceAnnouncement.events(for: configuration, at: now)
        let again = try AssumedPresenceAnnouncement.events(for: configuration, at: now + 60)

        #expect(events.count == 1)
        // The same assumption on a restart is the same source event, so the store dedupes it.
        #expect(events[0].source.sourceEventID == again[0].source.sourceEventID)
        let facts = try AssumedPersonPresenceReducer().reduce(events[0]).changedFacts
        #expect(facts.map(\.predicate) == [PresenceFacts.personState, PresenceFacts.personAudible])
        #expect(facts[0].value == .string("home"))
        #expect(facts[0].epistemic == (try EpistemicState(type: .assumed, confidence: 0.9)))
        #expect(facts[1].value == .bool(true))
    }

    @Test("A performed scene becomes the room's last scene for an hour")
    func performedSceneIsRemembered() throws {
        let event = try WorldEventEnvelope(
            type: SceneService.performedEventType,
            occurredAt: now,
            source: EventSource(id: SceneService.sourceID, kind: "world"),
            subjectIDs: [home, mango],
            placeID: home,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [
                "scene_id": .string("scene:1"),
                "trigger": .string("What is in the box?"),
                "lines": .array([
                    .object([
                        "character_id": .string("character:mango"), "text": .string("Heat sinks."),
                    ])
                ]),
            ]
        )

        let facts = try SceneMemoryReducer().reduce(event).changedFacts

        let fact = try #require(facts.first)
        #expect(fact.subjectID == home)
        #expect(fact.predicate == SceneMemoryReducer.predicate)
        #expect(fact.validTo == now.addingTimeInterval(3_600))
        guard case .object(let value) = fact.value else {
            Issue.record("expected an object value")
            return
        }
        #expect(value["trigger"] == .string("What is in the box?"))
    }

    private func sessionEvent(_ type: WorldEventType) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: type,
            occurredAt: now,
            source: EventSource(id: CharacterSessionService.sourceID, kind: "world"),
            subjectIDs: [mango, home],
            placeID: home,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [
                "character_id": .string(mango.rawValue),
                "region_id": .string(home.rawValue),
                "session_id": .string("character-session:1"),
            ]
        )
    }

    private func unrelatedEvent() throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: CharacterSessionService.loginEventType,
            occurredAt: now,
            source: EventSource(id: CharacterSessionService.sourceID, kind: "world"),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
    }
}

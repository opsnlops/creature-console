import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

@Suite(
    "Evidence over assumption",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct HousePresenceTests {
    @Test("The router reads an observed presence when the house has one, and assumes otherwise")
    func observedPresenceWins() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let april = try EntityID(validating: "person:april-\(UUID().uuidString.lowercased())")
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let assumptions = PresenceConfiguration(
            assumed: [april: try .init(state: .home, physicallyAudible: true, confidence: 0.9)])
        let provider = FactBackedPresenceProvider(
            facts: persistence.facts,
            fallback: AssumedPresenceProvider(configuration: assumptions, clock: clock),
            assumptions: assumptions, clock: clock)

        let assumed = try await provider.presence(for: april)
        #expect(assumed.basis == .assumed)
        #expect(assumed.state == .home)

        // The house saw April leave.
        try await persistence.facts.save(
            try Fact(
                subjectID: april, predicate: WorldFacts.personState, value: .string("away"),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: start.addingTimeInterval(-60), derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))

        let observed = try await provider.presence(for: april)
        #expect(observed.basis == .observed)
        #expect(observed.state == .away)
        #expect(observed.physicallyAudible == false)
        #expect(
            observed.validUntil == start.addingTimeInterval(FactBackedPresenceProvider.validity))
    }

    @Test("A scene ask goes to the house and comes back as the fact the mind is told")
    func sceneAskBecomesARequest() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let house = try EntityID(validating: "house:\(suffix)")
        // Scene names unique to this run: the shared database holds other houses' lists.
        let scene = "Evening \(suffix)"
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [HouseReducer()], clock: clock)
        try await persistence.facts.save(
            try Fact(
                subjectID: house, predicate: WorldFacts.houseScenes,
                value: .array([.string(scene), .string("Bedtime \(suffix)")]),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: start, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))
        let requests = HouseSceneRequests(
            facts: persistence.facts, world: world, clock: clock,
            logger: .init(label: "house-presence-tests"))
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-house"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Beaky, set the lights to \(scene)", modality: .typed,
            source: .communicatorComposition, sourceID: SourceID(validating: "communicator:test"),
            occurredAt: start, confidence: 1)

        let fact = try #require(try await requests.request(in: utterance))

        #expect(fact.subjectID == house)
        #expect(fact.predicate == WorldFacts.houseSceneRequested)
        #expect(fact.value == .string(scene))
        #expect(fact.validTo == start.addingTimeInterval(HouseSceneRequests.requestLifetime))
        guard case .event(let eventID)? = fact.derivedFrom.first else {
            Issue.record("the fact should come from the request event")
            return
        }
        let request = try #require(try await persistence.events.event(withID: eventID))
        #expect(request.type == HouseEvents.sceneRequested)
        #expect(request.payload["scene"] == .string(scene))
        #expect(request.source.sourceEventID == utterance.utteranceID.rawValue)
        // Not an ask: nothing happens.
        var mention = utterance
        mention.text = "I love an evening \(suffix)"
        #expect(try await requests.request(in: mention) == nil)
    }
}

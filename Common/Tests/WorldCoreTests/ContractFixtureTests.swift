import Foundation
import Testing

@testable import WorldCore

@Suite("WorldCore wire contract fixtures")
struct ContractFixtureTests {
    @Test("World event fixture round-trips semantically")
    func eventFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("world-event-v1", as: WorldEventEnvelope.self)
    }

    @Test("Fact fixture round-trips semantically")
    func factFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("world-fact-v1", as: Fact.self)
    }

    @Test("Timer fixture round-trips semantically")
    func timerFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("world-timer-v1", as: WorldTimer.self)
    }

    @Test("Percept fixture round-trips semantically")
    func perceptFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("perceptual-envelope-v1", as: PerceptualEnvelope.self)
    }

    @Test("Agent decision fixture round-trips semantically")
    func decisionFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("agent-decision-v1", as: AgentDecision.self)
    }

    @Test("Performance intent fixture round-trips semantically")
    func performanceFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("performance-intent-v1", as: PerformanceIntent.self)
    }

    @Test("Person utterance fixture round-trips semantically")
    func personUtteranceFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("person-utterance-v1", as: PersonUtterance.self)
    }

    @Test("Conversation item fixture round-trips semantically")
    func conversationItemFixtureRoundTrips() throws {
        try assertFixtureRoundTrip("conversation-item-v1", as: ConversationItem.self)
    }

    @Test("Person utterance percept fixture round-trips semantically")
    func personUtterancePerceptFixtureRoundTrips() throws {
        try assertFixtureRoundTrip(
            "person-utterance-percept-v1",
            as: PersonUtterancePercept.self
        )
    }

    @Test("Character utterance fixture round-trips semantically")
    func characterUtteranceFixtureRoundTrips() throws {
        try assertFixtureRoundTrip(
            "character-utterance-intent-v1",
            as: CharacterUtteranceIntent.self
        )
    }

    @Test("Delivery decision fixture round-trips semantically")
    func deliveryDecisionFixtureRoundTrips() throws {
        try assertFixtureRoundTrip(
            "character-delivery-decision-v1",
            as: CharacterDeliveryDecision.self
        )
    }

    @Test("Delivery outcome fixture round-trips semantically")
    func deliveryOutcomeFixtureRoundTrips() throws {
        try assertFixtureRoundTrip(
            "character-delivery-outcome-v1",
            as: CharacterDeliveryOutcome.self
        )
    }

    @Test("Every contract fixture has a parseable JSON Schema")
    func schemasArePresentAndParseable() throws {
        for name in [
            "world-event-v1",
            "world-fact-v1",
            "world-timer-v1",
            "perceptual-envelope-v1",
            "agent-decision-v1",
            "performance-intent-v1",
            "person-utterance-v1",
            "conversation-item-v1",
            "person-utterance-percept-v1",
            "character-utterance-intent-v1",
            "character-delivery-decision-v1",
            "character-delivery-outcome-v1",
        ] {
            let data = try Data(contentsOf: schemaURL(name))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
            #expect(object["$id"] != nil)
        }
    }

    private func assertFixtureRoundTrip<Value: Codable & Equatable>(
        _ name: String,
        as type: Value.Type
    ) throws {
        let original = try WorldJSON.makeDecoder().decode(
            Value.self,
            from: Data(contentsOf: fixtureURL(name))
        )
        let encoded = try WorldJSON.makeEncoder(prettyPrinted: true).encode(original)
        let decoded = try WorldJSON.makeDecoder().decode(Value.self, from: encoded)
        #expect(decoded == original)
    }
}

func fixtureURL(_ name: String) -> URL {
    packageRootURL
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("WorldCore", isDirectory: true)
        .appendingPathComponent("\(name).json")
}

func schemaURL(_ name: String) -> URL {
    packageRootURL
        .appendingPathComponent("Schemas", isDirectory: true)
        .appendingPathComponent("json", isDirectory: true)
        .appendingPathComponent("\(name).schema.json")
}

private let packageRootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

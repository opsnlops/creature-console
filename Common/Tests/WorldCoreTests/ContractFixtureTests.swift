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

    @Test("Every contract fixture has a parseable JSON Schema")
    func schemasArePresentAndParseable() throws {
        for name in [
            "world-event-v1",
            "world-fact-v1",
            "world-timer-v1",
            "perceptual-envelope-v1",
            "agent-decision-v1",
            "performance-intent-v1",
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

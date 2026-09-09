import Foundation
import Testing

@testable import WorldCore

@Suite("World contract validation")
struct ValidationTests {
    @Test("Unsupported event schema versions fail clearly")
    func unsupportedEventSchemaVersionFails() throws {
        let data = try dataWithSchemaVersion(2, fixture: "world-event-v1")
        #expect(
            throws: WorldContractError.unsupportedSchemaVersion(expected: 1, actual: 2)
        ) {
            try WorldJSON.makeDecoder().decode(WorldEventEnvelope.self, from: data)
        }
    }

    @Test("Uppercase event IDs normalize at the wire boundary")
    func uppercaseEventIDNormalizesDuringDecode() throws {
        let data = try Data(contentsOf: fixtureURL("world-event-v1"))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["event_id"] = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        let uppercaseData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try WorldJSON.makeDecoder().decode(
            WorldEventEnvelope.self,
            from: uppercaseData
        )
        let encoded = try WorldJSON.makeEncoder().encode(decoded)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(decoded.eventID.rawValue == "3f2504e0-4f89-41d3-9a0c-0305e82c3301")
        #expect(encodedObject["event_id"] as? String == decoded.eventID.rawValue)
    }

    @Test("Unsupported schemas fail for every top-level contract")
    func unsupportedSchemasFailForAllContracts() throws {
        let fact = try dataWithSchemaVersion(8, fixture: "world-fact-v1")
        let timer = try dataWithSchemaVersion(8, fixture: "world-timer-v1")
        let percept = try dataWithSchemaVersion(8, fixture: "perceptual-envelope-v1")
        let decision = try dataWithSchemaVersion(8, fixture: "agent-decision-v1")
        let performance = try dataWithSchemaVersion(8, fixture: "performance-intent-v1")

        #expect(throws: WorldContractError.self) {
            try WorldJSON.makeDecoder().decode(Fact.self, from: fact)
        }
        #expect(throws: WorldContractError.self) {
            try WorldJSON.makeDecoder().decode(WorldTimer.self, from: timer)
        }
        #expect(throws: WorldContractError.self) {
            try WorldJSON.makeDecoder().decode(PerceptualEnvelope.self, from: percept)
        }
        #expect(throws: WorldContractError.self) {
            try WorldJSON.makeDecoder().decode(AgentDecision.self, from: decision)
        }
        #expect(throws: WorldContractError.self) {
            try WorldJSON.makeDecoder().decode(PerformanceIntent.self, from: performance)
        }
    }

    @Test("Confidence and urgency reject non-finite and out-of-range values")
    func boundedValuesAreValidated() {
        #expect(throws: WorldContractError.self) {
            try EpistemicState(type: .observed, confidence: 1.01)
        }
        #expect(throws: WorldContractError.self) {
            try EpistemicState(type: .observed, confidence: .nan)
        }
    }

    @Test("Invalid W3C parent contexts are rejected")
    func invalidTraceParentsAreRejected() {
        #expect(throws: WorldContractError.self) {
            try W3CTraceContext(
                traceparent: "00-00000000000000000000000000000000-00f067aa0ba902b7-01"
            )
        }
        #expect(throws: WorldContractError.self) {
            try W3CTraceContext(
                traceparent: "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
            )
        }
    }

    @Test("Agent decisions reject contradictory action state")
    func contradictoryAgentDecisionsAreRejected() throws {
        let considerationID = ConsiderationID.generated()
        let characterID = try EntityID(validating: "character:beaky")

        #expect(throws: WorldContractError.inconsistentAgentDecision) {
            try AgentDecision(
                considerationID: considerationID,
                characterID: characterID,
                wantsToReact: true,
                confidence: 0.9,
                urgency: 0.5
            )
        }
        #expect(throws: WorldContractError.inconsistentAgentDecision) {
            try AgentDecision(
                considerationID: considerationID,
                characterID: characterID,
                wantsToReact: false,
                confidence: 0.9,
                intent: "React anyway",
                urgency: 0.5
            )
        }
    }

    @Test("Performance intents enforce their typed payload shape")
    func performanceIntentShapeIsValidated() throws {
        let characterID = try EntityID(validating: "character:beaky")

        #expect(throws: WorldContractError.invalidPerformanceIntent) {
            try PerformanceIntent(
                considerationID: .generated(),
                characterID: characterID,
                kind: .dialog,
                participants: [characterID],
                urgency: 0.5
            )
        }
        #expect(throws: WorldContractError.invalidPerformanceIntent) {
            try PerformanceIntent(
                considerationID: .generated(),
                characterID: characterID,
                kind: .animation,
                participants: [characterID],
                urgency: 0.5
            )
        }
    }

    @Test("Unknown additive fields are ignored")
    func unknownFieldsAreIgnored() throws {
        let data = try Data(contentsOf: fixtureURL("world-event-v1"))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["future_additive_field"] = ["safe": true]
        let extended = try JSONSerialization.data(withJSONObject: object)
        let event = try WorldJSON.makeDecoder().decode(WorldEventEnvelope.self, from: extended)
        #expect(event.type.rawValue == "device.access_point_changed")
    }

    @Test("Typed event payloads encode and decode through the envelope")
    func typedPayloadRoundTrips() throws {
        let payload = AccessPointChangedPayload(
            deviceID: try EntityID(validating: "device:april-phone"),
            accessPointID: try EntityID(validating: "device:workshop-ap"),
            connected: true
        )
        let envelope = try WorldEventEnvelope(
            occurredAt: Date(timeIntervalSince1970: 1_788_882_011),
            source: EventSource(
                id: try SourceID(validating: "adapter:home-assistant"),
                kind: "home_assistant"
            ),
            subjectIDs: [payload.deviceID],
            epistemic: EpistemicState(type: .observed, confidence: 0.98),
            payload: payload
        )

        #expect(try envelope.decodePayload(as: AccessPointChangedPayload.self) == payload)
    }

    private func dataWithSchemaVersion(_ version: Int, fixture: String) throws -> Data {
        let data = try Data(contentsOf: fixtureURL(fixture))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schema_version"] = version
        return try JSONSerialization.data(withJSONObject: object)
    }
}

private struct AccessPointChangedPayload: WorldEventPayload, Equatable {
    static let eventType = WorldEventType(rawValue: "device.access_point_changed")!

    let deviceID: EntityID
    let accessPointID: EntityID
    let connected: Bool

    private enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case accessPointID = "access_point_id"
        case connected
    }
}

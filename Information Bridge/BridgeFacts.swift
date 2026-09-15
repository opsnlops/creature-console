import Foundation
import WorldCore

/// The one shape the Bridge ever sends: a `facts.given` from `bridge:<source>`, with the item's
/// own id as the source event id so redelivery is a no-op and April can Forget it in the Viewer.
enum BridgeFacts {
    static let eventType = WorldEventType(rawValue: "facts.given")!
    static let sourceKind = "bridge"

    /// The Bridge as an entity of the world: its health is facts about it, like anything else.
    static let bridgeID = try! EntityID(validating: "thing:information-bridge")

    static func given(
        subject: EntityID, predicate: String, value: WorldJSONValue,
        validFor seconds: TimeInterval?,
        source: String, itemID: String, at now: Date = Date()
    ) throws -> WorldEventEnvelope {
        var payload: [String: WorldJSONValue] = [
            "subject_id": .string(subject.rawValue),
            "predicate": .string(predicate),
            "value": value,
        ]
        if let seconds {
            payload["valid_for_seconds"] = .number(seconds)
        }
        return try WorldEventEnvelope(
            type: eventType,
            occurredAt: now,
            source: EventSource(
                id: try SourceID(validating: "bridge:\(source)"), kind: sourceKind,
                sourceEventID: itemID),
            subjectIDs: [subject],
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: payload)
    }

    /// The Bridge's own heartbeat: `thing:information-bridge · bridge.online`, valid an hour, so
    /// a Bridge that stops is a fact that expires.
    static func online(version: String, host: String, at now: Date = Date()) throws
        -> WorldEventEnvelope
    {
        try given(
            subject: bridgeID, predicate: "bridge.online",
            value: .string("Information Bridge \(version) on \(host)"), validFor: 3_600,
            source: "app", itemID: "online:\(WorldJSON.timestamp(now))", at: now)
    }

    /// A test fact on the house, valid a minute: proves the road from this Mac to the world.
    static func hello(house: EntityID, version: String, host: String, at now: Date = Date())
        throws -> WorldEventEnvelope
    {
        try given(
            subject: house, predicate: "bridge.hello",
            value: .string("hello from Information Bridge \(version) on \(host)"), validFor: 60,
            source: "app", itemID: "hello:\(UUID().uuidString.lowercased())", at: now)
    }
}

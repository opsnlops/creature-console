import Foundation

public struct WorldEventType: RawRepresentable, Hashable, Sendable, Codable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
            components.allSatisfy({ component in
                !component.isEmpty
                    && component.utf8.allSatisfy { byte in
                        (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45
                            || byte == 95
                    }
            })
        else {
            throw WorldContractError.invalidEventType(rawValue)
        }
        self.rawValue = rawValue
    }

    public init?(rawValue: String) {
        try? self.init(validating: rawValue)
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct EventSource: Hashable, Sendable, Codable {
    public var id: SourceID
    public var kind: String
    public var sourceEventID: String?

    public init(id: SourceID, kind: String, sourceEventID: String? = nil) {
        self.id = id
        self.kind = kind
        self.sourceEventID = sourceEventID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sourceEventID = "source_event_id"
    }
}

public enum EpistemicType: String, Hashable, Sendable, Codable, CaseIterable {
    case observed
    case reported
    case scheduled
    case forecast
    case inferred
    case assumed
    case remembered
}

public struct EpistemicState: Hashable, Sendable, Codable {
    public var type: EpistemicType
    public var confidence: Double

    public init(type: EpistemicType, confidence: Double) throws {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw WorldContractError.invalidConfidence(confidence)
        }
        self.type = type
        self.confidence = confidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            type: container.decode(EpistemicType.self, forKey: .type),
            confidence: container.decode(Double.self, forKey: .confidence)
        )
    }
}

public struct W3CTraceContext: Hashable, Sendable, Codable {
    public var traceparent: String
    public var tracestate: String?
    public var baggage: String?

    public init(traceparent: String, tracestate: String? = nil, baggage: String? = nil) throws {
        guard Self.isValidTraceparent(traceparent) else {
            throw WorldContractError.invalidTraceParent(traceparent)
        }
        self.traceparent = traceparent.lowercased()
        self.tracestate = tracestate
        self.baggage = baggage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            traceparent: container.decode(String.self, forKey: .traceparent),
            tracestate: container.decodeIfPresent(String.self, forKey: .tracestate),
            baggage: container.decodeIfPresent(String.self, forKey: .baggage)
        )
    }

    private static func isValidTraceparent(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4,
            parts[0].count == 2,
            parts[1].count == 32,
            parts[2].count == 16,
            parts[3].count == 2
        else { return false }
        guard
            parts.allSatisfy({ part in
                part.utf8.allSatisfy { byte in
                    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70)
                        || (byte >= 97 && byte <= 102)
                }
            })
        else { return false }
        return parts[0].lowercased() != "ff"
            && parts[1] != "00000000000000000000000000000000"
            && parts[2] != "0000000000000000"
    }
}

public enum ProvenanceReference: Hashable, Sendable, Codable, CustomStringConvertible {
    case event(EventID)
    case fact(FactID)

    public var description: String {
        switch self {
        case .event(let id): id.rawValue
        case .fact(let id): id.rawValue
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let eventID = EventID(rawValue: value) {
            self = .event(eventID)
        } else {
            self = .fact(try FactID(validating: value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public protocol WorldEventPayload: Codable, Sendable {
    static var eventType: WorldEventType { get }
}

public struct WorldEventEnvelope: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var eventID: EventID
    public var type: WorldEventType
    public var occurredAt: Date
    public var observedAt: Date?
    public var receivedAt: Date?
    public var worldSequence: Int64?
    public var source: EventSource
    public var subjectIDs: [EntityID]
    public var placeID: EntityID?
    public var epistemic: EpistemicState
    public var payload: [String: WorldJSONValue]
    public var causedBy: [ProvenanceReference]
    public var trace: W3CTraceContext?

    public init(
        eventID: EventID = .generated(),
        type: WorldEventType,
        occurredAt: Date,
        observedAt: Date? = nil,
        receivedAt: Date? = nil,
        worldSequence: Int64? = nil,
        source: EventSource,
        subjectIDs: [EntityID],
        placeID: EntityID? = nil,
        epistemic: EpistemicState,
        payload: [String: WorldJSONValue],
        causedBy: [ProvenanceReference] = [],
        trace: W3CTraceContext? = nil
    ) throws {
        if let worldSequence, worldSequence < 1 {
            throw WorldContractError.invalidWorldSequence(worldSequence)
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.eventID = eventID
        self.type = type
        self.occurredAt = occurredAt
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.worldSequence = worldSequence
        self.source = source
        self.subjectIDs = subjectIDs
        self.placeID = placeID
        self.epistemic = epistemic
        self.payload = payload
        self.causedBy = causedBy
        self.trace = trace
    }

    public init<Payload: WorldEventPayload>(
        eventID: EventID = .generated(),
        occurredAt: Date,
        observedAt: Date? = nil,
        source: EventSource,
        subjectIDs: [EntityID],
        placeID: EntityID? = nil,
        epistemic: EpistemicState,
        payload: Payload,
        causedBy: [ProvenanceReference] = [],
        trace: W3CTraceContext? = nil
    ) throws {
        let encoded = try WorldJSON.makeEncoder().encode(payload)
        let jsonValue = try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: encoded)
        guard case .object(let object) = jsonValue else {
            throw WorldContractError.payloadIsNotObject
        }
        try self.init(
            eventID: eventID,
            type: Payload.eventType,
            occurredAt: occurredAt,
            observedAt: observedAt,
            source: source,
            subjectIDs: subjectIDs,
            placeID: placeID,
            epistemic: epistemic,
            payload: object,
            causedBy: causedBy,
            trace: trace
        )
    }

    public func decodePayload<Payload: WorldEventPayload>(as type: Payload.Type) throws -> Payload {
        guard self.type == Payload.eventType else {
            throw WorldContractError.invalidEventType(self.type.rawValue)
        }
        let encoded = try WorldJSON.makeEncoder().encode(WorldJSONValue.object(payload))
        return try WorldJSON.makeDecoder().decode(Payload.self, from: encoded)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        let worldSequence = try container.decodeIfPresent(Int64.self, forKey: .worldSequence)
        if let worldSequence, worldSequence < 1 {
            throw WorldContractError.invalidWorldSequence(worldSequence)
        }
        self.schemaVersion = schemaVersion
        self.eventID = try container.decode(EventID.self, forKey: .eventID)
        self.type = try container.decode(WorldEventType.self, forKey: .type)
        self.occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        self.observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        self.receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        self.worldSequence = worldSequence
        self.source = try container.decode(EventSource.self, forKey: .source)
        self.subjectIDs = try container.decode([EntityID].self, forKey: .subjectIDs)
        self.placeID = try container.decodeIfPresent(EntityID.self, forKey: .placeID)
        self.epistemic = try container.decode(EpistemicState.self, forKey: .epistemic)
        self.payload = try container.decode([String: WorldJSONValue].self, forKey: .payload)
        self.causedBy =
            try container.decodeIfPresent(
                [ProvenanceReference].self,
                forKey: .causedBy
            ) ?? []
        self.trace = try container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case type
        case occurredAt = "occurred_at"
        case observedAt = "observed_at"
        case receivedAt = "received_at"
        case worldSequence = "world_sequence"
        case source
        case subjectIDs = "subject_ids"
        case placeID = "place_id"
        case epistemic
        case payload
        case causedBy = "caused_by"
        case trace
    }
}

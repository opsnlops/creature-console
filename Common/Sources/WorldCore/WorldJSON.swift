import Foundation

public enum WorldContractError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(expected: Int, actual: Int)
    case invalidConfidence(Double)
    case invalidDateInterval
    case invalidEventType(String)
    case invalidTraceParent(String)
    case invalidWorldSequence(Int64)
    case payloadIsNotObject
    case inconsistentAgentDecision
    case invalidPerformanceIntent
    case emptyUtterance
    case invalidPersonUtterance
    case invalidConversationItem
    case invalidCharacterUtteranceIntent
    case conversationContentTooLarge(maximumUTF8Bytes: Int)
    case conversationContextTooLarge(maximumItems: Int)
    case conflictingConversationIdentity
    case invalidPresenceEvidence
    case inconsistentDeliveryDecision
    case unauthorizedUtteranceIngress
}

extension WorldContractError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let expected, let actual):
            "Unsupported world schema version \(actual); expected \(expected)"
        case .invalidConfidence(let value):
            "Expected a finite value between zero and one; received \(value)"
        case .invalidDateInterval:
            "The end of a validity interval cannot precede its start"
        case .invalidEventType(let value):
            "Invalid world event type: \(value)"
        case .invalidTraceParent(let value):
            "Invalid W3C traceparent: \(value)"
        case .invalidWorldSequence(let value):
            "World sequence must be positive; received \(value)"
        case .payloadIsNotObject:
            "A world event payload must encode as a JSON object"
        case .inconsistentAgentDecision:
            "A reaction requires an intent and participants; silence cannot contain an intent"
        case .invalidPerformanceIntent:
            "A dialog performance requires turns and an animation performance requires an ID"
        case .emptyUtterance:
            "An utterance must contain non-whitespace text"
        case .invalidPersonUtterance:
            "A person utterance must have one addressee and valid confidence"
        case .invalidConversationItem:
            "A conversation item must identify exactly one valid author and contain text"
        case .invalidCharacterUtteranceIntent:
            "A character utterance intent must contain text and valid urgency and expiry"
        case .conversationContentTooLarge(let maximumUTF8Bytes):
            "Conversation text exceeds the \(maximumUTF8Bytes)-byte limit"
        case .conversationContextTooLarge(let maximumItems):
            "Conversation context exceeds the \(maximumItems)-item limit"
        case .conflictingConversationIdentity:
            "A conversation identity was reused for different content"
        case .invalidPresenceEvidence:
            "Presence evidence must have valid confidence and freshness"
        case .inconsistentDeliveryDecision:
            "The selected delivery route and privacy mode are inconsistent"
        case .unauthorizedUtteranceIngress:
            "The utterance ingress boundary rejected the caller"
        }
    }
}

public enum WorldJSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([WorldJSONValue])
    case object([String: WorldJSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WorldJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: WorldJSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public enum WorldJSON {
    public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseDate(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an RFC 3339 timestamp"
                )
            }
            return date
        }
        return decoder
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }
}

public enum WorldSchema {
    public static let currentVersion = 1

    public static func validate(_ version: Int) throws {
        guard version == currentVersion else {
            throw WorldContractError.unsupportedSchemaVersion(
                expected: currentVersion,
                actual: version
            )
        }
    }
}

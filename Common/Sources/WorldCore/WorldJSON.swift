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
    case conversationContentTooLarge(maximumUnicodeScalars: Int)
    case conversationContextTooLarge(maximumItems: Int)
    case conflictingConversationIdentity
    case invalidPresenceEvidence
    case inconsistentDeliveryDecision
    case unauthorizedUtteranceIngress
    case invalidPerformanceReport
    case unstagedPerformance
    case characterSessionNotLive
    case invalidScene
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
        case .conversationContentTooLarge(let maximumUnicodeScalars):
            "Conversation text exceeds the \(maximumUnicodeScalars)-Unicode-scalar limit"
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
        case .invalidPerformanceReport:
            "A performance report must be performed or failed"
        case .unstagedPerformance:
            "A performance must be recorded against the stage decision the world made for it"
        case .characterSessionNotLive:
            "This mind does not hold a live session for the character"
        case .invalidScene:
            "A scene needs at least one participant and no participant twice"
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
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for element in value {
                try container.encode(element)
            }
        case .object(let value):
            var container = encoder.container(keyedBy: WorldJSONCodingKey.self)
            for (key, element) in value.sorted(by: { $0.key < $1.key }) {
                try container.encode(element, forKey: WorldJSONCodingKey(key))
            }
        }
    }
}

private struct WorldJSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
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

    /// The instant as it survives the wire and MongoDB: millisecond precision. Anything the
    /// world compares for identity after a round trip must be rounded first.
    public static func wireDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000)
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

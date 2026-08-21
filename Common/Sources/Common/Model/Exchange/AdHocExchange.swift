import Foundation

/// The lifecycle of a streamed ad-hoc exchange.
///
/// The server treats these as an open set of labels, so decoding is lenient:
/// a value this build doesn't know collapses to `.unknown` instead of failing
/// the whole payload.
public enum ExchangeStatus: String, Codable, Sendable, CaseIterable {
    case streaming
    case ready
    case partial
    case failed
    case unknown

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ExchangeStatus(rawValue: value) ?? .unknown
    }
}

/// One sentence of a streamed ad-hoc exchange, in playback order.
public struct AdHocExchangePart: Codable, Equatable, Sendable, Identifiable {
    public let index: UInt32
    public let animationId: AnimationIdentifier
    public let text: String
    public let durationMs: UInt64

    public var id: UInt32 { index }

    enum CodingKeys: String, CodingKey {
        case index
        case animationId = "animation_id"
        case text
        case durationMs = "duration_ms"
    }

    public init(index: UInt32, animationId: AnimationIdentifier, text: String, durationMs: UInt64) {
        self.index = index
        self.animationId = animationId
        self.text = text
        self.durationMs = durationMs
    }
}

/// One streamed ad-hoc session — everything a creature said in one
/// creature-agent-driven conversation turn, stitched by the server into a
/// single fully-tagged file (creature-server#150).
///
/// Session ids stay `String` (matching `StreamingAdHocDTO`): the server
/// compares them as strings, and round-tripping through `UUID` would
/// uppercase them.
public struct AdHocExchange: Codable, Equatable, Sendable, Identifiable {
    public let sessionId: String
    public let creatureId: CreatureIdentifier
    public let creatureName: String
    public let status: ExchangeStatus
    public let title: String
    public let transcript: String
    public let durationMs: UInt64
    public let createdAt: Date?
    public let finishedAt: Date?
    public let parts: [AdHocExchangePart]

    public var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case creatureId = "creature_id"
        case creatureName = "creature_name"
        case status
        case title
        case transcript
        case durationMs = "duration_ms"
        case createdAt = "created_at"
        case finishedAt = "finished_at"
        case parts
    }

    public init(
        sessionId: String,
        creatureId: CreatureIdentifier,
        creatureName: String,
        status: ExchangeStatus,
        title: String,
        transcript: String,
        durationMs: UInt64,
        createdAt: Date?,
        finishedAt: Date?,
        parts: [AdHocExchangePart]
    ) {
        self.sessionId = sessionId
        self.creatureId = creatureId
        self.creatureName = creatureName
        self.status = status
        self.title = title
        self.transcript = transcript
        self.durationMs = durationMs
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        creatureName = try container.decodeIfPresent(String.self, forKey: .creatureName) ?? ""
        status = try container.decodeIfPresent(ExchangeStatus.self, forKey: .status) ?? .unknown
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        durationMs = try container.decodeIfPresent(UInt64.self, forKey: .durationMs) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            .flatMap(AdHocExchange.parse)
        finishedAt = try container.decodeIfPresent(String.self, forKey: .finishedAt)
            .flatMap(AdHocExchange.parse)
        parts = try container.decodeIfPresent([AdHocExchangePart].self, forKey: .parts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(creatureName, forKey: .creatureName)
        try container.encode(status, forKey: .status)
        try container.encode(title, forKey: .title)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(durationMs, forKey: .durationMs)
        if let createdAt {
            try container.encode(AdHocExchange.format(createdAt), forKey: .createdAt)
        }
        if let finishedAt {
            try container.encode(AdHocExchange.format(finishedAt), forKey: .finishedAt)
        }
        try container.encode(parts, forKey: .parts)
    }

    /// The server emits whole-second ISO8601 (`2026-08-20T14:30:12Z`), but other
    /// list endpoints use fractional seconds — accept both.
    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: value)
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

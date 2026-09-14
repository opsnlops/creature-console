import Foundation

/// The world's current facts about some subjects, for a percept. Bounded so a mind's prompt
/// stays a window, never a dump.
public protocol WorldKnowledgeProviding: Sendable {
    /// Facts about `subjects`, and about anyone the world knows who is named in `text` — so a
    /// question about Polly carries what the world knows of Polly.
    func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
        async throws -> [Fact]

    /// What just happened around `subjects`: the recent events for them, oldest first. Facts
    /// are the present; the happenings are the story, and the story is where a mind works out
    /// that the door unlocking and then a person at the carport was April going out.
    func recentHappenings(about subjects: [EntityID], since: Date, limit: Int)
        async throws -> [Happening]

    /// What the given predicates mean, for the glossary a mind is handed beside the facts.
    func meanings(of predicates: Set<String>) async throws -> [String: String]
}

extension WorldKnowledgeProviding {
    public func currentFacts(about subjects: [EntityID], limit: Int) async throws -> [Fact] {
        try await currentFacts(about: subjects, mentionedIn: nil, limit: limit)
    }

    public func recentHappenings(about subjects: [EntityID], since: Date, limit: Int)
        async throws -> [Happening]
    {
        []
    }

    /// Without a store, the world's own catalogue.
    public func meanings(of predicates: Set<String>) async throws -> [String: String] {
        var meanings = WorldFacts.meanings.filter { predicates.contains($0.key) }
        for predicate in predicates where meanings[predicate] == nil {
            if let family = WorldFacts.memoryFamily(of: predicate) {
                meanings[predicate] = WorldFacts.meanings[family]
            }
        }
        return meanings
    }
}

/// One thing that happened, as a mind is told it: when, what kind, to whom or where, and the
/// world's own sentence for it when it has one. Never the payload.
public struct Happening: Codable, Hashable, Sendable {
    public var occurredAt: Date
    public var type: WorldEventType
    public var subjectID: EntityID
    public var summary: String?

    public init(occurredAt: Date, type: WorldEventType, subjectID: EntityID, summary: String? = nil)
    {
        self.occurredAt = occurredAt
        self.type = type
        self.subjectID = subjectID
        self.summary = summary
    }

    /// The kinds of event worth telling a mind about. Heartbeats, timers, pieces of lines, and
    /// measurements (state, already in the facts) are not a story.
    public static func isStoryworthy(_ type: WorldEventType) -> Bool {
        let raw = type.rawValue
        if raw == "camera.watching" || raw == "environment.measurement_changed" { return false }
        return ["door.", "camera.", "motion.", "person.", "house.", "facts."].contains {
            raw.hasPrefix($0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case type
        case subjectID = "subject_id"
        case summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        type = try container.decode(WorldEventType.self, forKey: .type)
        subjectID = try EntityID(validating: container.decode(String.self, forKey: .subjectID))
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(type, forKey: .type)
        try container.encode(subjectID.rawValue, forKey: .subjectID)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

/// The world before facts: nothing is known.
public struct NoWorldKnowledge: WorldKnowledgeProviding {
    public init() {}
    public func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
        async throws -> [Fact]
    {
        []
    }
}

public enum WorldMentions {
    /// The entities among `known` whose plain name ("polly" in `person:polly`) appears as a
    /// word in `text`, case-insensitively.
    public static func mentioned(in text: String, among known: [EntityID]) -> [EntityID] {
        let words = Set(
            text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return known.filter { id in
            let raw = id.rawValue
            guard let colon = raw.firstIndex(of: ":") else { return false }
            return words.contains(String(raw[raw.index(after: colon)...]).lowercased())
        }
    }
}

public enum WorldKnowledgeLimits {
    /// The most facts a single percept carries.
    public static let maximumFacts = 40
    /// How far back the story a percept carries reaches, and how many happenings at most.
    public static let happeningsWindow: TimeInterval = 15 * 60
    public static let maximumHappenings = 30
}

import Foundation

/// The world's current facts about some subjects, for a percept. Bounded so a mind's prompt
/// stays a window, never a dump.
public protocol WorldKnowledgeProviding: Sendable {
    /// Facts about `subjects`, and about anyone the world knows who is named in `text` — so a
    /// question about Polly carries what the world knows of Polly.
    func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
        async throws -> [Fact]
}

extension WorldKnowledgeProviding {
    public func currentFacts(about subjects: [EntityID], limit: Int) async throws -> [Fact] {
        try await currentFacts(about: subjects, mentionedIn: nil, limit: limit)
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
}

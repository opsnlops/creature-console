import Foundation

/// The world's current facts about some subjects, for a percept. Bounded so a mind's prompt
/// stays a window, never a dump.
public protocol WorldKnowledgeProviding: Sendable {
    func currentFacts(about subjects: [EntityID], limit: Int) async throws -> [Fact]
}

/// The world before facts: nothing is known.
public struct NoWorldKnowledge: WorldKnowledgeProviding {
    public init() {}
    public func currentFacts(about subjects: [EntityID], limit: Int) async throws -> [Fact] {
        []
    }
}

public enum WorldKnowledgeLimits {
    /// The most facts a single percept carries.
    public static let maximumFacts = 40
}

import CreatureAppSupport
import Foundation
import WorldCore

/// What the world holds under a family of facts, read back, so a source can take back what
/// it no longer wants even when its own ledger never knew it: facts cast by a Bridge on
/// another Mac, or before a ledger was lost. April deleted tomorrow's bloodwork; the laptop's
/// ledger had never cast it (cottontail's Bridge had), so nothing was there to retract, and
/// the world kept announcing it. The ledger is the Bridge's memory; the world is the truth
/// it must match.
struct WorldMirror: Sendable {
    typealias Read = @Sendable (_ predicatePrefix: String) async throws -> [Fact]

    let read: Read

    init(read: @escaping Read) { self.read = read }

    /// Every current fact with the prefix, paged, through the world's API.
    init(client: WorldViewerClient) {
        read = { prefix in
            var facts: [Fact] = []
            var after: FactID?
            repeat {
                let page = try await client.facts(predicatePrefix: prefix, after: after, limit: 200)
                facts += page.facts
                after = page.hasMore ? page.nextFactID : nil
            } while after != nil
            return facts
        }
    }

    /// What the world holds under `prefix`, by entity: the predicates each carries.
    func held(prefix: String) async throws -> [EntityID: Set<String>] {
        Dictionary(grouping: try await read(prefix), by: \.subjectID).mapValues {
            Set($0.map(\.predicate))
        }
    }

    /// The same, and the ghosts among them: entities the source does not want, keyed by
    /// entity with the predicates each carries. `keep` says which entities are the source's
    /// business at all (a calendar reads a window; an event outside it is not a ghost).
    func heldAndGhosts(
        prefix: String, wanted: Set<EntityID>, keep: (EntityID, [Fact]) -> Bool = { _, _ in true }
    ) async throws -> (held: [EntityID: Set<String>], ghosts: [EntityID: [String]]) {
        let facts = try await read(prefix)
        var held: [EntityID: Set<String>] = [:]
        var ghosts: [EntityID: [String]] = [:]
        for (entity, entityFacts) in Dictionary(grouping: facts, by: \.subjectID) {
            held[entity] = Set(entityFacts.map(\.predicate))
            if !wanted.contains(entity) && keep(entity, entityFacts) {
                ghosts[entity] = entityFacts.map(\.predicate).filter { $0.hasPrefix(prefix) }
                    .sorted()
            }
        }
        return (held, ghosts)
    }

    /// The facts under `prefix` on entities the source does not want - ghosts - keyed by
    /// entity, with the predicates each carries. `keep` says which entities are the source's
    /// business at all (a calendar reads a window; an event outside it is not a ghost).
    func ghosts(
        prefix: String, wanted: Set<EntityID>, keep: (EntityID, [Fact]) -> Bool = { _, _ in true }
    ) async throws -> [EntityID: [String]] {
        let held = try await read(prefix)
        var ghosts: [EntityID: [String]] = [:]
        for (entity, facts) in Dictionary(grouping: held, by: \.subjectID)
        where !wanted.contains(entity) && keep(entity, facts) {
            ghosts[entity] = facts.map(\.predicate).filter { $0.hasPrefix(prefix) }.sorted()
        }
        return ghosts
    }
}

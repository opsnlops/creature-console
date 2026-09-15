import Foundation
import MongoKitten
import WorldCore

/// `fact_kinds`: one document per predicate, keyed by it, holding what it means. The world
/// seeds it from its own catalogue and never overwrites a Wizard's rewording.
struct FactKindRepository: Sendable {
    private let kinds: MongoCollection

    init(database: MongoDatabase) {
        self.kinds = database[MongoWorldCollection.factKinds]
    }

    static let worldEditor = "world:catalogue"

    /// Adds every catalogue entry that has no document yet; existing ones are left alone.
    func seed(_ meanings: [String: String], at now: Date) async throws {
        for (predicate, meaning) in meanings {
            let query: Document = ["_id": predicate]
            let insert: Document = [
                "predicate": predicate, "meaning": meaning, "updated_at": now,
                "updated_by": Self.worldEditor,
            ]
            // An operator document as the upsert: inserted when absent, untouched when present.
            try await kinds.upsert(["$setOnInsert": insert], where: query)
        }
    }

    func all() async throws -> [FactKind] {
        let documents = try await kinds.find([:]).sort(["_id": 1]).drain()
        return try documents.map(decode)
    }

    func meanings(of predicates: Set<String>) async throws -> [String: String] {
        guard !predicates.isEmpty else { return [:] }
        let anyOf: Document = ["$in": Array(predicates)]
        let documents = try await kinds.find(["_id": anyOf]).drain()
        var meanings: [String: String] = [:]
        for kind in try documents.map(decode) {
            meanings[kind.predicate] = kind.meaning
        }
        return meanings
    }

    /// Sets the meaning; the audience too when given, else it stays as it was (`minds` new).
    func set(
        _ predicate: String, meaning: String, audience: FactAudience?, by editor: String,
        at now: Date
    ) async throws -> FactKind {
        let current = try await kinds.findOne(["_id": predicate]).map(decode)
        let kind = FactKind(
            predicate: predicate, meaning: meaning,
            audience: audience ?? current?.audience ?? .minds, updatedAt: now, updatedBy: editor)
        let document: Document = [
            "_id": predicate, "predicate": predicate, "meaning": meaning,
            "audience": kind.audience.rawValue, "updated_at": now, "updated_by": editor,
        ]
        try await kinds.upsert(document, where: ["_id": predicate])
        return kind
    }

    /// The predicates whose facts are the world's alone, never a mind's.
    func worldOnlyPredicates() async throws -> Set<String> {
        let documents = try await kinds.find(["audience": FactAudience.world.rawValue]).drain()
        return Set(try documents.map(decode).map(\.predicate))
    }

    private func decode(_ document: Document) throws -> FactKind {
        FactKind(
            predicate: document["predicate"] as? String ?? (document["_id"] as? String ?? ""),
            meaning: document["meaning"] as? String ?? "",
            audience: (document["audience"] as? String).flatMap(FactAudience.init(rawValue:))
                ?? .minds,
            updatedAt: document["updated_at"] as? Date ?? Date(timeIntervalSince1970: 0),
            updatedBy: document["updated_by"] as? String ?? Self.worldEditor)
    }
}

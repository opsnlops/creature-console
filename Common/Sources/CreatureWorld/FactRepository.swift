import Foundation
import MongoKitten
import WorldCore

struct FactRepository: Sendable {
    private let facts: MongoCollection

    init(database: MongoDatabase) {
        self.facts = database[MongoWorldCollection.facts]
    }

    /// A fact is current when nothing has replaced it and its validity window, if it has one,
    /// has not closed: `scene.last` is true for an hour and then simply stops being so.
    private func currentQuery(at now: Date) -> Document {
        [
            "superseded_by": Null(),
            "$or": [
                ["valid_to": Null()] as Document,
                ["valid_to": ["$gt": now] as Document] as Document,
            ] as Document,
        ]
    }

    func save(_ fact: Fact) async throws {
        var document = try BSONEncoder().encode(fact)
        document["_id"] = fact.factID.rawValue
        // BSONEncoder drops a nil; a fact whose value is `null` ("Beaky has left") must still
        // say so, or the document has no value at all and cannot be read back.
        if fact.value == .null {
            document["value"] = Null()
        }
        _ = try await facts.findOneAndUpsert(
            where: ["_id": fact.factID.rawValue],
            replacement: document,
            returnValue: .modified
        )
        .writeConcern(.majority())
        .execute()
    }

    func supersede(by fact: Fact) async throws {
        _ = try await facts.updateMany(
            where: [
                "subject_id": fact.subjectID.rawValue,
                "predicate": fact.predicate,
                "superseded_by": Null(),
                "_id": ["$ne": fact.factID.rawValue],
            ],
            to: [
                "$set": [
                    "valid_to": fact.validFrom,
                    "superseded_by": fact.factID.rawValue,
                ] as Document
            ]
        )
    }

    func currentFacts(subjectID: EntityID? = nil, at now: Date = Date()) async throws -> [Fact] {
        var query = currentQuery(at: now)
        if let subjectID {
            query["subject_id"] = subjectID.rawValue
        }
        let documents = try await facts.find(query).sort(["valid_from": 1]).drain()
        return try documents.map(decode)
    }

    /// Current facts about any of `subjects`, newest first, bounded.
    func currentFacts(about subjects: [EntityID], limit: Int, at now: Date) async throws
        -> [Fact]
    {
        precondition(limit > 0)
        guard !subjects.isEmpty else { return [] }
        var query = currentQuery(at: now)
        query["subject_id"] = ["$in": subjects.map(\.rawValue)] as Document
        let documents = try await facts.find(query)
            .sort(["valid_from": -1, "_id": -1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int, at now: Date)
        async throws -> [Fact]
    {
        precondition(limit > 0)
        var query = currentQuery(at: now)
        if let subjectID {
            query["subject_id"] = subjectID.rawValue
        }
        if let after {
            let greaterThan: Document = ["$gt": after.rawValue]
            query["_id"] = greaterThan
        }
        let documents = try await facts.find(query)
            .sort(["_id": 1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// The subjects that currently have a fact with `predicate` — the people the world can
    /// describe, for instance.
    func subjects(withPredicate predicate: String, at now: Date) async throws -> [EntityID] {
        var query = currentQuery(at: now)
        query["predicate"] = predicate
        let documents = try await facts.find(query).sort(["subject_id": 1]).drain()
        return documents.compactMap { document in
            (document["subject_id"] as? String).flatMap(EntityID.init(rawValue:))
        }
    }

    private func decode(_ document: Document) throws -> Fact {
        // Facts written before 0.8.0 with a `null` value have no `value` key at all, and the
        // BSON decoder cannot find a missing key; give it the null it meant.
        var readable = document
        if readable["value"] == nil {
            readable["value"] = Null()
        }
        var fact = try BSONDecoder().decode(Fact.self, from: readable)
        fact.value = try MongoWorldJSON.value(from: readable["value"] ?? Null())
        return fact
    }
}

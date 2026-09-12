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

    private func decode(_ document: Document) throws -> Fact {
        var fact = try BSONDecoder().decode(Fact.self, from: document)
        guard let value = document["value"] else {
            throw MongoWorldJSONError.missingObject
        }
        fact.value = try MongoWorldJSON.value(from: value)
        return fact
    }
}

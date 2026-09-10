import MongoKitten
import WorldCore

struct FactRepository: Sendable {
    private let facts: MongoCollection

    init(database: MongoDatabase) {
        self.facts = database[MongoWorldCollection.facts]
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

    func currentFacts(subjectID: EntityID? = nil) async throws -> [Fact] {
        var query: Document = [
            "valid_to": Null(),
            "superseded_by": Null(),
        ]
        if let subjectID {
            query["subject_id"] = subjectID.rawValue
        }
        return try await facts.find(query, as: Fact.self).sort(["valid_from": 1]).drain()
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws -> [Fact] {
        precondition(limit > 0)
        var query: Document = [
            "valid_to": Null(),
            "superseded_by": Null(),
        ]
        if let subjectID {
            query["subject_id"] = subjectID.rawValue
        }
        if let after {
            let greaterThan: Document = ["$gt": after.rawValue]
            query["_id"] = greaterThan
        }
        return try await facts.find(query, as: Fact.self)
            .sort(["_id": 1])
            .limit(limit)
            .drain()
    }
}

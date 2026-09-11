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
        let documents = try await facts.find(query).sort(["valid_from": 1]).drain()
        return try documents.map(decode)
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

import Foundation
import MongoKitten
import WorldCore

struct MongoConversationRepository: UtteranceIngressRepository, Sendable {
    private let ingresses: MongoCollection
    private let items: MongoCollection

    init(database: MongoDatabase) {
        ingresses = database[MongoWorldCollection.utteranceIngresses]
        items = database[MongoWorldCollection.conversationItems]
    }

    func ingress(for utteranceID: UtteranceID) async throws -> StoredUtteranceIngress? {
        guard
            let stored = try await ingresses.findOne(
                ["_id": utteranceID.rawValue],
                as: StoredUtteranceIngress.self
            )
        else { return nil }
        try await saveConversationItem(stored.conversationItem)
        return stored
    }

    func conversationItems(in conversationID: ConversationID) async throws -> [ConversationItem] {
        try await items.find(
            ["conversation_id": conversationID.rawValue],
            as: ConversationItem.self
        )
        .sort(["created_at": 1, "_id": 1])
        .drain()
    }

    func conversationItems(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> [ConversationItem] {
        precondition(limit > 0)
        var query: Document = ["conversation_id": conversationID.rawValue]
        if let itemID {
            guard
                let anchor = try await items.findOne(
                    ["_id": itemID.rawValue],
                    as: ConversationItem.self
                ), anchor.conversationID == conversationID
            else { throw WorldAPIError.invalidQuery(name: "after_item_id") }
            let laterDate: Document = ["created_at": ["$gt": anchor.createdAt]]
            let laterID: Document = [
                "created_at": anchor.createdAt,
                "_id": ["$gt": itemID.rawValue],
            ]
            query["$or"] = [laterDate, laterID]
        }
        return try await items.find(query, as: ConversationItem.self)
            .sort(["created_at": 1, "_id": 1])
            .limit(limit)
            .drain()
    }

    func prepare(_ proposed: StoredUtteranceIngress) async throws -> StoredUtteranceIngress {
        let utteranceID = proposed.percept.utterance.utteranceID
        var insertedValues = try BSONEncoder().encode(proposed)
        insertedValues["_id"] = utteranceID.rawValue
        let builder = ingresses.findOneAndUpdate(
            where: ["_id": utteranceID.rawValue],
            to: ["$setOnInsert": insertedValues],
            returnValue: .modified
        )
        builder.command.upsert = true
        let stored: StoredUtteranceIngress
        do {
            guard
                let accepted = try await builder.writeConcern(.majority()).decode(
                    StoredUtteranceIngress.self
                )
            else { throw WorldPersistenceError.missingUtteranceIngress }
            stored = accepted
        } catch {
            // A concurrent upsert may have won the unique utterance-ID race.
            guard
                let accepted = try await ingresses.findOne(
                    ["_id": utteranceID.rawValue],
                    as: StoredUtteranceIngress.self
                )
            else { throw error }
            stored = accepted
        }
        try await saveConversationItem(stored.conversationItem)
        return stored
    }

    func markPerceptSubmitted(utteranceID: UtteranceID) async throws {
        let builder = ingresses.findOneAndUpdate(
            where: ["_id": utteranceID.rawValue],
            to: ["$set": ["progress": UtteranceIngressProgress.perceptSubmitted.rawValue]],
            returnValue: .modified
        )
        guard
            try await builder.writeConcern(.majority()).decode(StoredUtteranceIngress.self) != nil
        else { throw WorldPersistenceError.missingUtteranceIngress }
    }

    /// Persists one canonical conversation item exactly once. Both April's utterances and
    /// Beaky's responses share this write path so the conversation stays one ordered history.
    func saveConversationItem(_ item: ConversationItem) async throws {
        var document = try BSONEncoder().encode(item)
        document["_id"] = item.itemID.rawValue
        let builder = items.findOneAndUpdate(
            where: ["_id": item.itemID.rawValue],
            to: ["$setOnInsert": document],
            returnValue: .modified
        )
        builder.command.upsert = true
        guard
            let stored = try await builder.writeConcern(.majority()).decode(ConversationItem.self)
        else { throw WorldPersistenceError.missingConversationItem }
        guard stored == item else {
            throw WorldContractError.conflictingConversationIdentity
        }
    }
}

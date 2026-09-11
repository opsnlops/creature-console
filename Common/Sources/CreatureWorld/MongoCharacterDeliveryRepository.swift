import Foundation
import MongoKitten
import WorldCore

/// Durable record of where and how one Beaky turn was delivered.
///
/// The `character_deliveries` document is keyed by the intent's stable `response_id`, so a retry,
/// restart, or concurrent presence transition finds the first durable decision instead of making a
/// second one. The canonical `ConversationItem` is written into `conversation_items` inside
/// `prepare`, before any delivery sink runs, so a turn performed aloud and a turn synchronized to
/// Communicator share one ordered history with April's utterances.
struct MongoCharacterDeliveryRepository: CharacterDeliveryRepository, Sendable {
    private let deliveries: MongoCollection
    private let conversations: MongoConversationRepository

    init(database: MongoDatabase) {
        deliveries = database[MongoWorldCollection.characterDeliveries]
        conversations = MongoConversationRepository(database: database)
    }

    func delivery(for responseID: ResponseID) async throws -> StoredCharacterDelivery? {
        guard
            let stored = try await deliveries.findOne(
                ["_id": responseID.rawValue],
                as: StoredCharacterDelivery.self
            )
        else { return nil }
        try await conversations.saveConversationItem(stored.conversationItem)
        return stored
    }

    func prepare(_ proposed: StoredCharacterDelivery) async throws -> StoredCharacterDelivery {
        let responseID = proposed.intent.responseID
        var insertedValues = try BSONEncoder().encode(proposed)
        insertedValues["_id"] = responseID.rawValue
        let builder = deliveries.findOneAndUpdate(
            where: ["_id": responseID.rawValue],
            to: ["$setOnInsert": insertedValues],
            returnValue: .modified
        )
        builder.command.upsert = true
        let stored: StoredCharacterDelivery
        do {
            guard
                let accepted = try await builder.writeConcern(.majority()).decode(
                    StoredCharacterDelivery.self
                )
            else { throw WorldPersistenceError.missingCharacterDelivery }
            stored = accepted
        } catch {
            // A concurrent upsert may have won the unique response-ID race.
            guard
                let accepted = try await deliveries.findOne(
                    ["_id": responseID.rawValue],
                    as: StoredCharacterDelivery.self
                )
            else { throw error }
            stored = accepted
        }
        try await conversations.saveConversationItem(stored.conversationItem)
        return stored
    }

    func record(_ outcome: CharacterDeliveryOutcome) async throws {
        let encoded = try BSONEncoder().encode(outcome)
        let builder = deliveries.findOneAndUpdate(
            where: ["_id": outcome.responseID.rawValue],
            to: ["$set": ["outcome": encoded]],
            returnValue: .modified
        )
        guard
            try await builder.writeConcern(.majority()).decode(StoredCharacterDelivery.self) != nil
        else { throw WorldPersistenceError.missingCharacterDelivery }
    }
}

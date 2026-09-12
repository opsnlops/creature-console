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
    private let stageDecisions: MongoCollection
    private let conversations: MongoConversationRepository

    init(database: MongoDatabase) {
        deliveries = database[MongoWorldCollection.characterDeliveries]
        stageDecisions = database[MongoWorldCollection.characterStageDecisions]
        conversations = MongoConversationRepository(database: database)
    }

    func stageDecision(for responseID: ResponseID) async throws -> StoredStageDecision? {
        try await stageDecisions.findOne(
            ["_id": responseID.rawValue],
            as: StoredStageDecision.self
        )
    }

    func prepareStage(_ proposed: StoredStageDecision) async throws -> StoredStageDecision {
        let responseID = proposed.decision.responseID
        var insertedValues = try BSONEncoder().encode(proposed)
        insertedValues["_id"] = responseID.rawValue
        let builder = stageDecisions.findOneAndUpdate(
            where: ["_id": responseID.rawValue],
            to: ["$setOnInsert": insertedValues],
            returnValue: .modified
        )
        builder.command.upsert = true
        do {
            guard
                let accepted = try await builder.writeConcern(.majority()).decode(
                    StoredStageDecision.self
                )
            else { throw WorldPersistenceError.missingCharacterDelivery }
            return accepted
        } catch {
            // A concurrent upsert may have won the unique response-ID race.
            guard
                let accepted = try await stageDecisions.findOne(
                    ["_id": responseID.rawValue],
                    as: StoredStageDecision.self
                )
            else { throw error }
            return accepted
        }
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

    /// Deliveries in one conversation in the order the character spoke, paged by response ID.
    func deliveries(
        in conversationID: ConversationID,
        after responseID: ResponseID?,
        limit: Int
    ) async throws -> [StoredCharacterDelivery] {
        precondition(limit > 0)
        var query: Document = ["intent.conversation_id": conversationID.rawValue]
        if let responseID {
            guard
                let anchor = try await deliveries.findOne(
                    ["_id": responseID.rawValue],
                    as: StoredCharacterDelivery.self
                ), anchor.intent.conversationID == conversationID
            else { throw WorldAPIError.invalidQuery(name: "after_response_id") }
            let later: Document = ["intent.created_at": ["$gt": anchor.intent.createdAt]]
            let sameInstant: Document = [
                "intent.created_at": anchor.intent.createdAt,
                "_id": ["$gt": responseID.rawValue],
            ]
            query["$or"] = [later, sameInstant]
        }
        return try await deliveries.find(query, as: StoredCharacterDelivery.self)
            .sort(["intent.created_at": 1, "_id": 1])
            .limit(limit)
            .drain()
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

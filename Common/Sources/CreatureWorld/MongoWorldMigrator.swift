import Foundation
import Logging
import MongoKitten

struct MongoWorldMigrator: Sendable {
    static let currentVersion = 6

    let database: MongoDatabase
    let logger: Logger

    func migrate() async throws {
        logger.debug("Ensuring world event indexes")
        try await createEventIndexes()
        logger.debug("Ensuring fact indexes")
        try await createFactIndexes()
        logger.debug("Ensuring timer indexes")
        try await createTimerIndexes()
        logger.debug("Ensuring source checkpoint indexes")
        try await createSourceCheckpointIndexes()
        logger.debug("Ensuring conversation indexes")
        try await createConversationIndexes()
        logger.debug("Ensuring character delivery indexes")
        try await createCharacterDeliveryIndexes()
        logger.debug("Ensuring character stage decision indexes")
        try await createCharacterStageDecisionIndexes()
        logger.debug("Ensuring character session indexes")
        try await createCharacterSessionIndexes()

        try await recordMigration(version: 1, name: "initial_world_repositories")
        try await recordMigration(version: 2, name: "world_event_processing")
        try await recordMigration(version: 3, name: "conversation_ingress")
        try await recordMigration(version: 4, name: "character_delivery")
        try await recordMigration(version: 5, name: "character_stage_decision")
        try await recordMigration(version: 6, name: "character_session")
        logger.debug(
            "MongoDB schema migrations recorded",
            metadata: ["mongodb.migration_version": "\(Self.currentVersion)"]
        )
    }

    private func recordMigration(version: Int, name: String) async throws {
        let insertedValues: Document = ["name": name, "applied_at": Date()]
        let builder = database[MongoWorldCollection.schemaMigrations].findOneAndUpdate(
            where: ["_id": version],
            to: ["$setOnInsert": insertedValues],
            returnValue: .modified
        )
        builder.command.upsert = true
        _ = try await builder.writeConcern(.majority()).execute()
    }

    private func createEventIndexes() async throws {
        var eventID = CreateIndexes.Index(named: "event_id_unique", keys: ["event_id": 1])
        eventID.unique = true

        var sequence = CreateIndexes.Index(
            named: "world_sequence_unique",
            keys: ["world_sequence": 1]
        )
        sequence.unique = true

        var sourceEvent = CreateIndexes.Index(
            named: "source_event_unique",
            keys: [
                "source.id": 1,
                "source.source_event_id": 1,
            ]
        )
        sourceEvent.unique = true
        let stringType: Document = ["$type": "string"]
        sourceEvent.partialFilterExpression = ["source.source_event_id": stringType]

        let typeAndOccurrence = CreateIndexes.Index(
            named: "type_occurred_at",
            keys: [
                "type": 1,
                "occurred_at": 1,
            ]
        )
        let subjects = CreateIndexes.Index(named: "subject_ids", keys: ["subject_ids": 1])

        try await database[MongoWorldCollection.events].createIndexes([
            eventID,
            sequence,
            sourceEvent,
            typeAndOccurrence,
            subjects,
        ])
    }

    private func createFactIndexes() async throws {
        var factID = CreateIndexes.Index(named: "fact_id_unique", keys: ["fact_id": 1])
        factID.unique = true
        let activeFacts = CreateIndexes.Index(
            named: "active_facts",
            keys: [
                "subject_id": 1,
                "predicate": 1,
                "valid_to": 1,
                "superseded_by": 1,
            ]
        )
        try await database[MongoWorldCollection.facts].createIndexes([factID, activeFacts])
    }

    private func createTimerIndexes() async throws {
        var timerID = CreateIndexes.Index(named: "timer_id_unique", keys: ["timer_id": 1])
        timerID.unique = true
        let pendingTimers = CreateIndexes.Index(
            named: "pending_timers",
            keys: [
                "status": 1,
                "due_at": 1,
            ]
        )
        try await database[MongoWorldCollection.timers].createIndexes([timerID, pendingTimers])
    }

    private func createSourceCheckpointIndexes() async throws {
        var sourceID = CreateIndexes.Index(named: "source_id_unique", keys: ["source_id": 1])
        sourceID.unique = true
        try await database[MongoWorldCollection.sourceCheckpoints].createIndexes([sourceID])
    }

    private func createConversationIndexes() async throws {
        var utteranceID = CreateIndexes.Index(
            named: "utterance_id_unique",
            keys: [
                "percept.utterance.utterance_id": 1
            ])
        utteranceID.unique = true

        var itemID = CreateIndexes.Index(
            named: "conversation_item_id_unique",
            keys: [
                "item_id": 1
            ])
        itemID.unique = true
        let conversationOrder = CreateIndexes.Index(
            named: "conversation_order",
            keys: [
                "conversation_id": 1,
                "created_at": 1,
                "_id": 1,
            ]
        )
        try await database[MongoWorldCollection.utteranceIngresses].createIndexes([utteranceID])
        try await database[MongoWorldCollection.conversationItems].createIndexes([
            itemID, conversationOrder,
        ])
    }

    private func createCharacterDeliveryIndexes() async throws {
        var attemptID = CreateIndexes.Index(
            named: "delivery_attempt_id_unique",
            keys: [
                "decision.attempt_id": 1
            ])
        attemptID.unique = true
        let conversationResponses = CreateIndexes.Index(
            named: "conversation_responses",
            keys: [
                "intent.conversation_id": 1,
                "intent.created_at": 1,
            ]
        )
        try await database[MongoWorldCollection.characterDeliveries].createIndexes([
            attemptID, conversationResponses,
        ])
    }

    private func createCharacterSessionIndexes() async throws {
        let byCharacter = CreateIndexes.Index(
            named: "character_sessions_by_character",
            keys: ["character_id": 1, "logged_in_at": -1]
        )
        try await database[MongoWorldCollection.characterSessions].createIndexes([byCharacter])
    }

    /// Stage decisions are promises about *where*, made before the words exist; MongoDB expires
    /// them once `expires_at` passes so a mind that never followed through leaves nothing behind.
    private func createCharacterStageDecisionIndexes() async throws {
        var expiry = CreateIndexes.Index(
            named: "stage_decision_expiry",
            keys: ["expires_at": 1]
        )
        expiry.expireAfterSeconds = 0
        try await database[MongoWorldCollection.characterStageDecisions].createIndexes([expiry])
    }
}

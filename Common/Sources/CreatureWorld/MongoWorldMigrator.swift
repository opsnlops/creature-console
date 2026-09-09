import Foundation
import MongoKitten

struct MongoWorldMigrator: Sendable {
    static let currentVersion = 1

    let database: MongoDatabase

    func migrate() async throws {
        try await createEventIndexes()
        try await createFactIndexes()
        try await createTimerIndexes()
        try await createSourceCheckpointIndexes()

        let insertedValues: Document = [
            "name": "initial_world_repositories",
            "applied_at": Date(),
        ]
        let migration: Document = ["$setOnInsert": insertedValues]
        let builder = database[MongoWorldCollection.schemaMigrations].findOneAndUpdate(
            where: ["_id": Self.currentVersion],
            to: migration,
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
}

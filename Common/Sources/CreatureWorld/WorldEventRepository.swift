import Foundation
import MongoKitten
import WorldCore

enum EventAppendResult: Equatable, Sendable {
    case inserted(WorldEventEnvelope)
    case duplicateEvent(WorldEventEnvelope)
    case duplicateSourceEvent(WorldEventEnvelope)
}

struct WorldEventRepository: Sendable {
    private let events: MongoCollection
    private let eventProcessing: MongoCollection
    private let counters: MongoCollection

    init(database: MongoDatabase) {
        self.events = database[MongoWorldCollection.events]
        self.eventProcessing = database[MongoWorldCollection.eventProcessing]
        self.counters = database[MongoWorldCollection.counters]
    }

    func append(_ proposedEvent: WorldEventEnvelope, receivedAt: Date = Date()) async throws
        -> EventAppendResult
    {
        if let existing = try await event(withID: proposedEvent.eventID) {
            return .duplicateEvent(existing)
        }
        if let existing = try await event(withSource: proposedEvent.source) {
            return .duplicateSourceEvent(existing)
        }

        var acceptedEvent = proposedEvent
        acceptedEvent.receivedAt = receivedAt
        acceptedEvent.worldSequence = try await nextSequence()

        var document = try BSONEncoder().encode(acceptedEvent)
        document["_id"] = acceptedEvent.eventID.rawValue
        do {
            try await events.insert(document, writeConcern: .majority())
            return .inserted(acceptedEvent)
        } catch {
            // A concurrent append may have won either unique-key race after our preflight.
            if let existing = try await event(withID: proposedEvent.eventID) {
                return .duplicateEvent(existing)
            }
            if let existing = try await event(withSource: proposedEvent.source) {
                return .duplicateSourceEvent(existing)
            }
            throw error
        }
    }

    func event(withID eventID: EventID) async throws -> WorldEventEnvelope? {
        try await events.findOne(["event_id": eventID.rawValue], as: WorldEventEnvelope.self)
    }

    func events(after sequence: Int64) async throws -> [WorldEventEnvelope] {
        let greaterThan: Document = ["$gt": Int(sequence)]
        return
            try await events
            .find(["world_sequence": greaterThan], as: WorldEventEnvelope.self)
            .sort(["world_sequence": 1])
            .drain()
    }

    func isProcessed(eventID: EventID) async throws -> Bool {
        try await eventProcessing.findOne(["_id": eventID.rawValue]) != nil
    }

    func markProcessed(eventID: EventID, processedAt: Date) async throws {
        let insertedValues: Document = [
            "event_id": eventID.rawValue,
            "processed_at": processedAt,
        ]
        let builder = eventProcessing.findOneAndUpdate(
            where: ["_id": eventID.rawValue],
            to: ["$setOnInsert": insertedValues],
            returnValue: .modified
        )
        builder.command.upsert = true
        _ = try await builder.writeConcern(.majority()).execute()
    }

    private func event(withSource source: EventSource) async throws -> WorldEventEnvelope? {
        guard let sourceEventID = source.sourceEventID else { return nil }
        return try await events.findOne(
            [
                "source.id": source.id.rawValue,
                "source.source_event_id": sourceEventID,
            ],
            as: WorldEventEnvelope.self
        )
    }

    private func nextSequence() async throws -> Int64 {
        let increment: Document = ["value": 1]
        let builder = counters.findOneAndUpdate(
            where: ["_id": "world_sequence"],
            to: ["$inc": increment],
            returnValue: .modified
        )
        builder.command.upsert = true
        builder.command.writeConcern = .majority()
        let counter = try await builder.decode(SequenceCounter.self)
        return try counter.unwrap(or: WorldPersistenceError.missingSequenceCounter).value
    }
}

private struct SequenceCounter: Decodable, Sendable {
    let value: Int64
}

enum WorldPersistenceError: Error, Equatable, Sendable {
    case missingSequenceCounter
}

extension Optional {
    fileprivate func unwrap(or error: @autoclosure () -> any Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}

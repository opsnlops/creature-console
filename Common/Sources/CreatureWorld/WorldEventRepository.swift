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
    private let retention: RetentionPolicy

    init(database: MongoDatabase, retention: RetentionPolicy = RetentionPolicy()) {
        self.events = database[MongoWorldCollection.events]
        self.eventProcessing = database[MongoWorldCollection.eventProcessing]
        self.counters = database[MongoWorldCollection.counters]
        self.retention = retention
    }

    func append(_ proposedEvent: WorldEventEnvelope, receivedAt: Date) async throws
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
        // When this stops mattering, by kind: the TTL index on expires_at does the rest.
        document["expires_at"] = retention.expiry(
            for: acceptedEvent.type, occurredAt: acceptedEvent.occurredAt)
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
        guard let document = try await events.findOne(["event_id": eventID.rawValue]) else {
            return nil
        }
        return try decode(document)
    }

    func events(after sequence: Int64, limit: Int) async throws -> [WorldEventEnvelope] {
        precondition(limit > 0)
        let greaterThan: Document = ["$gt": Int(sequence)]
        let documents =
            try await events
            .find(["world_sequence": greaterThan])
            .sort(["world_sequence": 1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// The events about any of `subjects` since `since`, oldest first — the story a mind is
    /// told. Callers filter by kind; this is the index-shaped query.
    func events(about subjects: [EntityID], since: Date, limit: Int) async throws
        -> [WorldEventEnvelope]
    {
        precondition(limit > 0)
        guard !subjects.isEmpty else { return [] }
        let anyOf: Document = ["$in": subjects.map(\.rawValue)]
        let after: Document = ["$gte": since]
        let documents =
            try await events
            .find(["subject_ids": anyOf, "occurred_at": after])
            .sort(["occurred_at": 1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// Everything that happened in a window, oldest first — a day, for the memory job.
    func events(from start: Date, to end: Date, limit: Int) async throws -> [WorldEventEnvelope] {
        precondition(limit > 0)
        let window: Document = ["$gte": start, "$lt": end]
        let documents =
            try await events
            .find(["occurred_at": window])
            .sort(["occurred_at": 1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// Every event in the window, oldest first, read in pages by sequence until there are no
    /// more - a day of the house is thousands of events, and one capped read of it ended at
    /// 6:35 PM and lost the evening. `ceiling` is the sanity limit, not a page size.
    func allEvents(from start: Date, to end: Date, pageSize: Int = 2_000, ceiling: Int = 100_000)
        async throws -> [WorldEventEnvelope]
    {
        precondition(pageSize > 0)
        let window: Document = ["$gte": start, "$lt": end]
        var all: [WorldEventEnvelope] = []
        var after: Int64 = -1
        while all.count < ceiling {
            let greaterThan: Document = ["$gt": Int(after)]
            let documents =
                try await events
                .find(["occurred_at": window, "world_sequence": greaterThan])
                .sort(["world_sequence": 1])
                .limit(pageSize)
                .drain()
            let page = try documents.map(decode)
            all += page
            guard page.count == pageSize, let last = page.last?.worldSequence else { break }
            after = last
        }
        return all.sorted { $0.occurredAt < $1.occurredAt }
    }

    func latestSequence() async throws -> Int64 {
        let document = try await events.find([:])
            .sort(["world_sequence": -1])
            .limit(1)
            .drain()
            .first
        return try document.map(decode)?.worldSequence ?? 0
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
        guard
            let document = try await events.findOne(
                [
                    "source.id": source.id.rawValue,
                    "source.source_event_id": sourceEventID,
                ])
        else { return nil }
        return try decode(document)
    }

    private func decode(_ document: Document) throws -> WorldEventEnvelope {
        var event = try BSONDecoder().decode(WorldEventEnvelope.self, from: document)
        event.payload = try MongoWorldJSON.object(from: document["payload"])
        return event
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
    case missingUtteranceIngress
    case missingConversationItem
    case missingCharacterDelivery
}

extension Optional {
    fileprivate func unwrap(or error: @autoclosure () -> any Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}

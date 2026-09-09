import Foundation
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

@Suite(
    "Creature World MongoDB persistence",
    .serialized,
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests")
)
struct MongoWorldPersistenceTests {
    @Test("Migration creates the required repository indexes")
    func createsRequiredIndexes() async throws {
        try await withPersistence { persistence in
            let eventIndexes = try await persistence.database[MongoWorldCollection.events]
                .listIndexes().drain()
            let factIndexes = try await persistence.database[MongoWorldCollection.facts]
                .listIndexes().drain()
            let timerIndexes = try await persistence.database[MongoWorldCollection.timers]
                .listIndexes().drain()

            #expect(eventIndexes.contains { $0.name == "event_id_unique" && $0.unique == true })
            #expect(
                eventIndexes.contains { $0.name == "world_sequence_unique" && $0.unique == true }
            )
            #expect(eventIndexes.contains { $0.name == "source_event_unique" && $0.unique == true })
            #expect(factIndexes.contains { $0.name == "active_facts" })
            #expect(timerIndexes.contains { $0.name == "pending_timers" })
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 1]) != nil
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 2]) != nil
            )
        }
    }

    @Test("Duplicate event and source identities are idempotent")
    func duplicateEventsAreIdempotent() async throws {
        try await withPersistence { persistence in
            let sourceEventID = UUID().uuidString.lowercased()
            let first = try makeEvent(sourceEventID: sourceEventID)

            let inserted = try await persistence.events.append(first)
            let duplicateID = try await persistence.events.append(first)
            let duplicateSource = try await persistence.events.append(
                makeEvent(sourceID: first.source.id, sourceEventID: sourceEventID)
            )

            let accepted = try #require(inserted.insertedEvent)
            #expect(accepted.worldSequence != nil)
            let duplicateByID = try #require(duplicateID.duplicateEvent)
            let duplicateBySource = try #require(duplicateSource.duplicateSourceEvent)
            #expect(duplicateByID.eventID == accepted.eventID)
            #expect(duplicateByID.worldSequence == accepted.worldSequence)
            #expect(duplicateBySource.eventID == accepted.eventID)
            #expect(duplicateBySource.worldSequence == accepted.worldSequence)

            #expect(try await !persistence.events.isProcessed(eventID: accepted.eventID))
            try await persistence.events.markProcessed(
                eventID: accepted.eventID,
                processedAt: Date()
            )
            #expect(try await persistence.events.isProcessed(eventID: accepted.eventID))
            let immutableEvent = try await persistence.database[MongoWorldCollection.events]
                .findOne(["_id": accepted.eventID.rawValue])
            #expect(immutableEvent?["processed_at"] == nil)
            #expect(
                try await persistence.database[MongoWorldCollection.eventProcessing]
                    .findOne(["_id": accepted.eventID.rawValue]) != nil
            )
        }
    }

    @Test("Concurrent event appends receive unique increasing sequences")
    func concurrentSequencesAreUnique() async throws {
        try await withPersistence { persistence in
            let inserted = try await withThrowingTaskGroup(
                of: WorldEventEnvelope.self,
                returning: [WorldEventEnvelope].self
            ) { group in
                for _ in 0..<20 {
                    group.addTask {
                        let result = try await persistence.events.append(makeEvent())
                        return try #require(result.insertedEvent)
                    }
                }

                var events: [WorldEventEnvelope] = []
                for try await event in group {
                    events.append(event)
                }
                return events
            }

            let sequences = try inserted.map { try #require($0.worldSequence) }
            #expect(Set(sequences).count == inserted.count)
            #expect(sequences.allSatisfy { $0 > 0 })
        }
    }

    @Test("Current facts survive a database reconnect")
    func restartReadsCurrentFacts() async throws {
        let uri = try #require(mongoTestURI)
        let subjectID = try EntityID(validating: "person:\(UUID().uuidString.lowercased())")
        let current = try Fact(
            subjectID: subjectID,
            predicate: "location.current",
            value: .string("place:workshop"),
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: Date(),
            derivedFrom: [],
            producer: FactProducer(kind: "test", id: "mongo", version: "1")
        )

        let firstConnection = try await MongoWorldPersistence.connect(
            to: uri,
            logger: .init(label: "creature-world-mongodb-tests")
        )
        try await firstConnection.facts.save(current)
        await firstConnection.cluster.disconnect()

        let secondConnection = try await MongoWorldPersistence.connect(
            to: uri,
            logger: .init(label: "creature-world-mongodb-tests")
        )
        let reloaded = try await secondConnection.facts.currentFacts(subjectID: subjectID)
        await secondConnection.cluster.disconnect()

        let reloadedFact = try #require(reloaded.only)
        #expect(reloadedFact.factID == current.factID)
        #expect(reloadedFact.subjectID == current.subjectID)
        #expect(reloadedFact.predicate == current.predicate)
        #expect(reloadedFact.value == current.value)
    }

    @Test("Repeated fact saves replace one durable document")
    func repeatedFactSavesAreIdempotent() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let factID = try FactID(validating: "fact:\(suffix)")
            let subjectID = try EntityID(validating: "person:\(suffix)")
            let original = try Fact(
                factID: factID,
                subjectID: subjectID,
                predicate: "location.current",
                value: .string("place:workshop"),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: Date(),
                derivedFrom: [],
                producer: FactProducer(kind: "test", id: "mongo", version: "1")
            )
            var replacement = original
            replacement.value = .string("place:stage")

            try await persistence.facts.save(original)
            try await persistence.facts.save(replacement)

            let documents = try await persistence.database[MongoWorldCollection.facts]
                .find(["_id": factID.rawValue], as: Fact.self)
                .drain()
            let stored = try #require(documents.only)
            #expect(stored.factID == factID)
            #expect(stored.value == replacement.value)
        }
    }

    @Test("Timer and source checkpoint repositories round trip")
    func timerAndCheckpointRoundTrip() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let sourceID = try SourceID(validating: "test:\(suffix)")
            let timer = WorldTimer(
                timerID: try TimerID(validating: "timer:\(suffix)"),
                purpose: try WorldEventType(validating: "test.timer-fired"),
                dueAt: Date().addingTimeInterval(60),
                subjectIDs: [],
                causedBy: [],
                payload: [:]
            )
            let checkpoint = SourceCheckpoint(
                sourceID: sourceID,
                value: .string("cursor-42"),
                updatedAt: Date()
            )

            try await persistence.timers.save(timer)
            try await persistence.sourceCheckpoints.save(checkpoint)

            let reloadedTimer = try #require(
                try await persistence.timers.pending().first { $0.timerID == timer.timerID }
            )
            let reloadedCheckpoint = try #require(
                try await persistence.sourceCheckpoints.checkpoint(for: sourceID)
            )
            #expect(reloadedTimer.purpose == timer.purpose)
            #expect(reloadedTimer.status == .pending)
            #expect(reloadedCheckpoint.sourceID == checkpoint.sourceID)
            #expect(reloadedCheckpoint.value == checkpoint.value)
        }
    }

    private func withPersistence<T: Sendable>(
        _ operation: @Sendable (MongoWorldPersistence) async throws -> T
    ) async throws -> T {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI),
            logger: .init(label: "creature-world-mongodb-tests")
        )
        do {
            let result = try await operation(persistence)
            await persistence.cluster.disconnect()
            return result
        } catch {
            await persistence.cluster.disconnect()
            throw error
        }
    }

    private func makeEvent(sourceID: SourceID? = nil, sourceEventID: String? = nil) throws
        -> WorldEventEnvelope
    {
        let resolvedSourceID =
            try sourceID
            ?? SourceID(validating: "test:\(UUID().uuidString.lowercased())")
        return try WorldEventEnvelope(
            type: WorldEventType(validating: "test.observed"),
            occurredAt: Date(),
            source: EventSource(
                id: resolvedSourceID,
                kind: "test",
                sourceEventID: sourceEventID
            ),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
    }
}

extension EventAppendResult {
    fileprivate var insertedEvent: WorldEventEnvelope? {
        guard case .inserted(let event) = self else { return nil }
        return event
    }

    fileprivate var duplicateEvent: WorldEventEnvelope? {
        guard case .duplicateEvent(let event) = self else { return nil }
        return event
    }

    fileprivate var duplicateSourceEvent: WorldEventEnvelope? {
        guard case .duplicateSourceEvent(let event) = self else { return nil }
        return event
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

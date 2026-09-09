import Foundation
import InMemoryTracing
import Instrumentation
import Testing
import Tracing
import WorldCore

@testable import creature_world

@Suite("Authoritative World actor")
struct WorldTests {
    @Test("Concurrent submissions remain ordered while persistence is suspended")
    func concurrentSubmissionsAreOrdered() async throws {
        let store = TestWorldStore(blockFirstAppend: true)
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [],
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        let stream = try await world.subscribe()
        var iterator = stream.makeAsyncIterator()
        let firstEvent = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000001",
            sourceEventID: "source-1"
        )
        let secondEvent = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000002",
            sourceEventID: "source-2"
        )

        let firstTask = Task { try await world.accept(firstEvent) }
        while await store.appendAttemptCount == 0 {
            await Task.yield()
        }

        let secondTask = Task { try await world.accept(secondEvent) }
        while await world.pendingEventCount < 2 {
            await Task.yield()
        }

        // The actor remains responsive while the first persistence operation is suspended.
        #expect(await world.pendingEventCount == 2)
        await store.releaseFirstAppend()

        let firstAcceptance = try await firstTask.value
        let secondAcceptance = try await secondTask.value
        let firstDelta = try #require(await iterator.next())
        let secondDelta = try #require(await iterator.next())

        #expect(firstAcceptance.disposition == .accepted)
        #expect(secondAcceptance.disposition == .accepted)
        #expect(firstAcceptance.event.worldSequence == 1)
        #expect(secondAcceptance.event.worldSequence == 2)
        #expect(firstDelta.event.eventID == firstEvent.eventID)
        #expect(secondDelta.event.eventID == secondEvent.eventID)
        #expect(await store.appendedEventIDs == [firstEvent.eventID, secondEvent.eventID])
        #expect(await world.pendingEventCount == 0)
    }

    @Test("Reducers emit ordered facts, derived events, and subscription deltas")
    func reducersAndDerivedEventsAreDeterministic() async throws {
        let store = TestWorldStore()
        let rootType = try WorldEventType(validating: "test.root")
        let derivedType = try WorldEventType(validating: "test.derived")
        let derivedEventID = try EventID(validating: "00000000-0000-0000-0000-000000000011")
        let factID = try FactID(validating: "fact:00000000-0000-0000-0000-000000000012")
        let derivedEvent = try makeEvent(
            eventID: derivedEventID.rawValue,
            type: derivedType,
            sourceEventID: "derived-1"
        )
        let rootReducer = TestWorldReducer(eventTypes: [rootType]) { _ in
            WorldReduction(derivedEvents: [derivedEvent])
        }
        let derivedReducer = TestWorldReducer(eventTypes: [derivedType]) { event in
            let fact = try Fact(
                factID: factID,
                subjectID: try EntityID(validating: "place:workshop"),
                predicate: "test.last-event",
                value: .string(event.eventID.rawValue),
                epistemic: EpistemicState(type: .inferred, confidence: 1),
                validFrom: Self.receivedAt,
                derivedFrom: [.event(event.eventID)],
                producer: FactProducer(kind: "reducer", id: "test", version: "1")
            )
            return WorldReduction(changedFacts: [fact])
        }
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [rootReducer, derivedReducer],
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        let stream = try await world.subscribe()
        var iterator = stream.makeAsyncIterator()
        let rootEvent = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000010",
            type: rootType,
            sourceEventID: "root-1"
        )

        let acceptance = try await world.accept(rootEvent)
        let rootDelta = try #require(await iterator.next())
        let derivedDelta = try #require(await iterator.next())

        #expect(acceptance.disposition == .accepted)
        #expect(rootDelta.event.eventID == rootEvent.eventID)
        #expect(rootDelta.event.worldSequence == 1)
        #expect(rootDelta.changedFacts.isEmpty)
        #expect(derivedDelta.event.eventID == derivedEventID)
        #expect(derivedDelta.event.worldSequence == 2)
        #expect(derivedDelta.event.causedBy == [.event(rootEvent.eventID)])
        #expect(derivedDelta.changedFacts.map(\.factID) == [factID])
        #expect(await store.savedFactIDs == [factID])
        #expect(await world.publishedDeltaCount == 2)

        let duplicate = try await world.accept(rootEvent)
        #expect(duplicate.disposition == .duplicateEvent)
        #expect(duplicate.event.worldSequence == 1)
        #expect(await store.savedFactIDs == [factID])
        #expect(await world.publishedDeltaCount == 2)
    }

    @Test("Duplicate source events are not reduced or published")
    func duplicateSourceEventsAreIdempotent() async throws {
        let store = TestWorldStore()
        let eventType = try WorldEventType(validating: "test.observed")
        let factID = try FactID(validating: "fact:00000000-0000-0000-0000-000000000022")
        let reducer = TestWorldReducer(eventTypes: [eventType]) { event in
            WorldReduction(changedFacts: [try makeFact(factID: factID, event: event)])
        }
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [reducer],
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        let first = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000020",
            type: eventType,
            sourceEventID: "same-source-event"
        )
        let duplicateSource = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000021",
            type: eventType,
            sourceEventID: "same-source-event"
        )

        let accepted = try await world.accept(first)
        let duplicate = try await world.accept(duplicateSource)

        #expect(accepted.disposition == .accepted)
        #expect(duplicate.disposition == .duplicateSourceEvent)
        #expect(duplicate.event.eventID == first.eventID)
        #expect(await store.savedFactIDs == [factID])
        #expect(await world.publishedDeltaCount == 1)
    }

    @Test("Matching reducers run in registration order")
    func reducersRunInRegistrationOrder() async throws {
        let store = TestWorldStore()
        let eventType = try WorldEventType(validating: "test.ordered")
        let firstFactID = try FactID(
            validating: "fact:00000000-0000-0000-0000-000000000031"
        )
        let secondFactID = try FactID(
            validating: "fact:00000000-0000-0000-0000-000000000032"
        )
        let unrelatedType = try WorldEventType(validating: "test.unrelated")
        let reducers = [
            TestWorldReducer(eventTypes: [eventType]) { event in
                WorldReduction(
                    changedFacts: [try makeFact(factID: firstFactID, event: event)]
                )
            },
            TestWorldReducer(eventTypes: [unrelatedType]) { _ in
                Issue.record("An unrelated reducer was dispatched")
                return WorldReduction()
            },
            TestWorldReducer(eventTypes: [eventType]) { event in
                WorldReduction(
                    changedFacts: [try makeFact(factID: secondFactID, event: event)]
                )
            },
        ]
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: reducers,
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        let stream = try await world.subscribe()
        var iterator = stream.makeAsyncIterator()
        let event = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000030",
            type: eventType,
            sourceEventID: "ordered-1"
        )

        _ = try await world.accept(event)
        let delta = try #require(await iterator.next())

        #expect(delta.changedFacts.map(\.factID) == [firstFactID, secondFactID])
        #expect(await store.savedFactIDs == [firstFactID, secondFactID])
    }

    @Test("An accepted event is safely retried after reducer output persistence fails")
    func acceptedEventCanBeRetried() async throws {
        let store = TestWorldStore(failFirstFactSave: true)
        let eventType = try WorldEventType(validating: "test.retry")
        let factID = try FactID(validating: "fact:00000000-0000-0000-0000-000000000041")
        let reducer = TestWorldReducer(eventTypes: [eventType]) { event in
            WorldReduction(changedFacts: [try makeFact(factID: factID, event: event)])
        }
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [reducer],
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        let event = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000040",
            type: eventType,
            sourceEventID: "retry-1"
        )

        await #expect(throws: TestWorldStoreError.factSaveFailed) {
            try await world.accept(event)
        }
        let retried = try await world.accept(event)

        #expect(retried.disposition == .duplicateEvent)
        #expect(await store.savedFactIDs == [factID])
        #expect(await store.processedEventIDsSnapshot == [event.eventID])
        #expect(await world.publishedDeltaCount == 1)
    }

    @Test("A causal batch cannot emit an unbounded number of derived events")
    func derivedEventsAreBounded() async throws {
        let store = TestWorldStore()
        let eventType = try WorldEventType(validating: "test.fanout")
        let firstDerived = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000051",
            type: eventType,
            sourceEventID: "fanout-child-1"
        )
        let secondDerived = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000052",
            type: eventType,
            sourceEventID: "fanout-child-2"
        )
        let reducer = TestWorldReducer(eventTypes: [eventType]) { event in
            guard event.causedBy.isEmpty else { return WorldReduction() }
            return WorldReduction(derivedEvents: [firstDerived, secondDerived])
        }
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [reducer],
            clock: FixedWorldClock(now: Self.receivedAt),
            limits: WorldLimits(maximumDerivedEventsPerAcceptance: 1)
        )
        let event = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000050",
            type: eventType,
            sourceEventID: "fanout-root"
        )

        await #expect(throws: WorldProcessingError.derivedEventLimitExceeded(limit: 1)) {
            try await world.accept(event)
        }
        #expect(await store.processedEventIDsSnapshot.isEmpty)
        #expect(await world.publishedDeltaCount == 0)
    }

    @Test("A partial completion-marker failure cannot hide a derived delta")
    func partialMarkerFailurePreservesAtLeastOnceDeltas() async throws {
        let store = TestWorldStore(failMarkAttempt: 2)
        let rootType = try WorldEventType(validating: "test.marker-root")
        let derivedType = try WorldEventType(validating: "test.marker-derived")
        let derived = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000054",
            type: derivedType,
            sourceEventID: "marker-child"
        )
        let reducer = TestWorldReducer(eventTypes: [rootType]) { _ in
            WorldReduction(derivedEvents: [derived])
        }
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [reducer],
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        let root = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000053",
            type: rootType,
            sourceEventID: "marker-root"
        )

        await #expect(throws: TestWorldStoreError.markProcessedFailed) {
            try await world.accept(root)
        }
        _ = try await world.accept(root)

        #expect(await world.publishedDeltaCount == 3)
        #expect(await store.processedEventIDsSnapshot == Set([root.eventID, derived.eventID]))
    }

    @Test("The acceptance queue rejects excess work while persistence is stalled")
    func acceptanceQueueIsBounded() async throws {
        let store = TestWorldStore(blockFirstAppend: true)
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [],
            clock: FixedWorldClock(now: Self.receivedAt),
            limits: WorldLimits(maximumPendingAcceptances: 1)
        )
        let first = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000055",
            sourceEventID: "queue-1"
        )
        let second = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000056",
            sourceEventID: "queue-2"
        )
        let firstTask = Task { try await world.accept(first) }
        while await store.appendAttemptCount == 0 {
            await Task.yield()
        }

        await #expect(throws: WorldProcessingError.queueFull(limit: 1)) {
            try await world.accept(second)
        }
        await store.releaseFirstAppend()
        _ = try await firstTask.value

        #expect(await store.appendedEventIDs == [first.eventID])
        #expect(await world.pendingEventCount == 0)
    }

    @Test("A slow subscriber is disconnected instead of consuming unbounded memory")
    func slowSubscriberIsDisconnected() async throws {
        let store = TestWorldStore()
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [],
            clock: FixedWorldClock(now: Self.receivedAt),
            limits: WorldLimits(subscriptionBufferCapacity: 1)
        )
        let stream = try await world.subscribe()
        var iterator = stream.makeAsyncIterator()
        let first = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000060",
            sourceEventID: "subscriber-1"
        )
        let second = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000061",
            sourceEventID: "subscriber-2"
        )

        _ = try await world.accept(first)
        _ = try await world.accept(second)

        #expect(try await iterator.next()?.event.eventID == first.eventID)
        await #expect(
            throws: WorldSubscriptionError.fellBehind(bufferCapacity: 1)
        ) {
            try await iterator.next()
        }
    }

    @Test("The actor bounds the number of live subscriptions")
    func subscriptionCountIsBounded() async throws {
        let store = TestWorldStore()
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [],
            clock: FixedWorldClock(now: Self.receivedAt),
            limits: WorldLimits(maximumSubscriptions: 1)
        )

        let firstSubscription = try await world.subscribe()
        _ = firstSubscription
        await #expect(
            throws: WorldSubscriptionError.subscriptionLimitReached(limit: 1)
        ) {
            try await world.subscribe()
        }
    }

    @Test("Processing spans preserve parent context and exclude event payloads")
    func processingTelemetryIsPrivacySafeAndConnected() async throws {
        let tracer = InMemoryTracer()
        InstrumentationSystem.bootstrap(tracer)
        let store = TestWorldStore()
        let world = World(
            eventStore: store,
            factStore: store,
            reducers: [],
            clock: FixedWorldClock(now: Self.receivedAt)
        )
        var event = try makeEvent(
            eventID: "00000000-0000-0000-0000-000000000070",
            sourceEventID: "telemetry-1"
        )
        let privateValue = "private payload must not reach telemetry"
        event.payload["private"] = .string(privateValue)

        try await withSpan("test.ingress") { _ in
            _ = try await world.accept(event)
        }

        let spans = tracer.finishedSpans
        let ingressSpan = try #require(spans.first { $0.operationName == "test.ingress" })
        let acceptanceSpan = try #require(
            spans.first {
                $0.operationName == "world.event.accept"
                    && $0.attributes.get("world.event.id")
                        == .string("00000000-0000-0000-0000-000000000070")
            }
        )
        let processingSpan = try #require(
            spans.first {
                $0.operationName == "world.event.process"
                    && $0.attributes.get("world.event.id")
                        == .string("00000000-0000-0000-0000-000000000070")
            }
        )

        #expect(acceptanceSpan.parentSpanID == ingressSpan.spanID)
        #expect(processingSpan.parentSpanID == acceptanceSpan.spanID)
        #expect(processingSpan.traceID == ingressSpan.traceID)
        #expect(
            processingSpan.attributes.get("world.event.id")
                == .string("00000000-0000-0000-0000-000000000070"))
        #expect(processingSpan.attributes.get("world.event.type") == .string("test.observed"))
        #expect(!String(describing: acceptanceSpan.attributes).contains(privateValue))
        #expect(!String(describing: processingSpan.attributes).contains(privateValue))
    }

    private static let receivedAt = Date(timeIntervalSince1970: 1_789_000_000)

    private func makeEvent(
        eventID: String,
        type: WorldEventType? = nil,
        sourceEventID: String
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            eventID: EventID(validating: eventID),
            type: type ?? WorldEventType(validating: "test.observed"),
            occurredAt: Date(timeIntervalSince1970: 1_788_999_000),
            source: EventSource(
                id: try SourceID(validating: "test:source"),
                kind: "test",
                sourceEventID: sourceEventID
            ),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
    }

    private func makeFact(factID: FactID, event: WorldEventEnvelope) throws -> Fact {
        try Fact(
            factID: factID,
            subjectID: EntityID(validating: "place:workshop"),
            predicate: "test.last-event",
            value: .string(event.eventID.rawValue),
            epistemic: EpistemicState(type: .inferred, confidence: 1),
            validFrom: Self.receivedAt,
            derivedFrom: [.event(event.eventID)],
            producer: FactProducer(kind: "reducer", id: "test", version: "1")
        )
    }
}

private struct FixedWorldClock: WorldClock {
    let now: Instant

    func sleep(until deadline: Instant) async throws {}
}

private struct TestWorldReducer: WorldReducer {
    let eventTypes: Set<WorldEventType>
    private let operation: @Sendable (WorldEventEnvelope) throws -> WorldReduction

    init(
        eventTypes: Set<WorldEventType>,
        operation: @escaping @Sendable (WorldEventEnvelope) throws -> WorldReduction
    ) {
        self.eventTypes = eventTypes
        self.operation = operation
    }

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        return try operation(event)
    }
}

private enum TestWorldStoreError: Error {
    case factSaveFailed
    case markProcessedFailed
}

private actor TestWorldStore: WorldEventStore, WorldFactStore {
    private let blockFirstAppend: Bool
    private var failFirstFactSave: Bool
    private let failMarkAttempt: Int?
    private var acceptedByEventID: [EventID: WorldEventEnvelope] = [:]
    private var acceptedBySourceEvent: [String: WorldEventEnvelope] = [:]
    private var appendAttempts: [EventID] = []
    private var facts: [Fact] = []
    private var processedEventIDs: Set<EventID> = []
    private var firstAppendReleased = false
    private var markAttempts = 0
    private var nextSequence: Int64 = 1

    init(
        blockFirstAppend: Bool = false,
        failFirstFactSave: Bool = false,
        failMarkAttempt: Int? = nil
    ) {
        self.blockFirstAppend = blockFirstAppend
        self.failFirstFactSave = failFirstFactSave
        self.failMarkAttempt = failMarkAttempt
    }

    var appendAttemptCount: Int { appendAttempts.count }
    var appendedEventIDs: [EventID] { appendAttempts }
    var savedFactIDs: [FactID] { facts.map(\.factID) }
    var processedEventIDsSnapshot: Set<EventID> { processedEventIDs }

    func append(_ event: WorldEventEnvelope, receivedAt: Date) async throws -> EventAppendResult {
        appendAttempts.append(event.eventID)
        if blockFirstAppend, appendAttempts.count == 1 {
            while !firstAppendReleased {
                await Task.yield()
            }
        }

        if let existing = acceptedByEventID[event.eventID] {
            return .duplicateEvent(existing)
        }
        if let sourceEventID = event.source.sourceEventID,
            let existing = acceptedBySourceEvent[sourceKey(event.source.id, sourceEventID)]
        {
            return .duplicateSourceEvent(existing)
        }

        var accepted = event
        accepted.receivedAt = receivedAt
        accepted.worldSequence = nextSequence
        nextSequence += 1
        acceptedByEventID[accepted.eventID] = accepted
        if let sourceEventID = accepted.source.sourceEventID {
            acceptedBySourceEvent[sourceKey(accepted.source.id, sourceEventID)] = accepted
        }
        return .inserted(accepted)
    }

    func save(_ fact: Fact) async throws {
        if failFirstFactSave {
            failFirstFactSave = false
            throw TestWorldStoreError.factSaveFailed
        }
        facts.append(fact)
    }

    func isProcessed(eventID: EventID) -> Bool {
        processedEventIDs.contains(eventID)
    }

    func markProcessed(eventID: EventID, processedAt: Date) throws {
        markAttempts += 1
        if markAttempts == failMarkAttempt {
            throw TestWorldStoreError.markProcessedFailed
        }
        processedEventIDs.insert(eventID)
    }

    func releaseFirstAppend() {
        firstAppendReleased = true
    }

    private func sourceKey(_ sourceID: SourceID, _ sourceEventID: String) -> String {
        "\(sourceID.rawValue):\(sourceEventID)"
    }
}

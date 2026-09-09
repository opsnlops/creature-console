import Foundation
import Metrics
import Tracing
import WorldCore

enum WorldEventDisposition: String, Equatable, Sendable {
    case accepted
    case duplicateEvent = "duplicate_event"
    case duplicateSourceEvent = "duplicate_source_event"
}

struct WorldEventAcceptance: Equatable, Sendable {
    let disposition: WorldEventDisposition
    let event: WorldEventEnvelope
}

struct WorldDelta: Equatable, Sendable {
    let event: WorldEventEnvelope
    let changedFacts: [Fact]
}

struct WorldLimits: Equatable, Sendable {
    static let `default` = WorldLimits()

    let maximumPendingAcceptances: Int
    let maximumDerivedEventsPerAcceptance: Int
    let maximumSubscriptions: Int
    let subscriptionBufferCapacity: Int

    init(
        maximumPendingAcceptances: Int = 1_024,
        maximumDerivedEventsPerAcceptance: Int = 1_024,
        maximumSubscriptions: Int = 256,
        subscriptionBufferCapacity: Int = 256
    ) {
        precondition(maximumPendingAcceptances > 0)
        precondition(maximumDerivedEventsPerAcceptance >= 0)
        precondition(maximumSubscriptions > 0)
        precondition(subscriptionBufferCapacity > 0)
        self.maximumPendingAcceptances = maximumPendingAcceptances
        self.maximumDerivedEventsPerAcceptance = maximumDerivedEventsPerAcceptance
        self.maximumSubscriptions = maximumSubscriptions
        self.subscriptionBufferCapacity = subscriptionBufferCapacity
    }
}

enum WorldProcessingError: Error, Equatable, LocalizedError, Sendable {
    case queueFull(limit: Int)
    case derivedEventLimitExceeded(limit: Int)
    case missingRootAcceptance

    var errorDescription: String? {
        switch self {
        case .queueFull(let limit):
            "Creature World event queue is full (limit: \(limit))"
        case .derivedEventLimitExceeded(let limit):
            "A causal event batch exceeded the derived-event limit (limit: \(limit))"
        case .missingRootAcceptance:
            "Creature World processing completed without a root event acceptance"
        }
    }
}

enum WorldSubscriptionError: Error, Equatable, LocalizedError, Sendable {
    case subscriptionLimitReached(limit: Int)
    case fellBehind(bufferCapacity: Int)

    var errorDescription: String? {
        switch self {
        case .subscriptionLimitReached(let limit):
            "Creature World subscription limit reached (limit: \(limit))"
        case .fellBehind(let bufferCapacity):
            "World subscription fell behind its delta buffer (capacity: \(bufferCapacity)); reconnect and request a fresh snapshot"
        }
    }
}

typealias WorldDeltaStream = AsyncThrowingStream<WorldDelta, any Error>

actor World {
    private let limits: WorldLimits
    private let processor: WorldEventProcessor
    private let reducers: [any WorldReducer]
    private let telemetry: WorldTelemetry
    private var pendingEventCountStorage = 0
    private var publishedDeltaCountStorage = 0
    private var processingTail: Task<Void, Never>?
    private var subscribers: [UUID: WorldDeltaStream.Continuation] = [:]

    init(
        eventStore: any WorldEventStore,
        factStore: any WorldFactStore,
        reducers: [any WorldReducer],
        clock: any WorldClock = SystemWorldClock(),
        limits: WorldLimits = .default
    ) {
        let telemetry = WorldTelemetry()
        self.limits = limits
        self.processor = WorldEventProcessor(
            eventStore: eventStore,
            factStore: factStore,
            clock: clock,
            maximumDerivedEvents: limits.maximumDerivedEventsPerAcceptance,
            telemetry: telemetry
        )
        self.reducers = reducers
        self.telemetry = telemetry
    }

    var pendingEventCount: Int {
        pendingEventCountStorage
    }

    var publishedDeltaCount: Int {
        publishedDeltaCountStorage
    }

    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        return try await withSpan("world.event.accept") { span in
            Self.setEventAttributes(on: span, event: event)
            telemetry.receivedCounter.increment()
            try Task.checkCancellation()
            guard pendingEventCountStorage < limits.maximumPendingAcceptances else {
                span.attributes["world.event.disposition"] = "rejected"
                span.attributes["world.rejection.reason"] = "queue_full"
                telemetry.rejectedCounter.increment()
                throw WorldProcessingError.queueFull(limit: limits.maximumPendingAcceptances)
            }

            let previous = processingTail
            let processor = self.processor
            pendingEventCountStorage += 1
            telemetry.queueDepthGauge.record(pendingEventCountStorage)

            // @concurrent keeps persistence and reducer orchestration off the actor while Task
            // still inherits the acceptance span's task-local trace context.
            let work = Task { @concurrent in
                if let previous {
                    await previous.value
                }

                do {
                    let acceptance = try await processor.process(
                        event,
                        reduce: { acceptedEvent in
                            try await self.reduce(acceptedEvent)
                        },
                        publish: { deltas in
                            await self.publish(deltas)
                        }
                    )
                    await self.processingFinished()
                    return acceptance
                } catch {
                    await self.processingFinished()
                    throw error
                }
            }
            processingTail = Task {
                _ = try? await work.value
            }

            let acceptance = try await work.value
            span.attributes["world.event.disposition"] = acceptance.disposition.rawValue
            if let sequence = acceptance.event.worldSequence {
                span.attributes["world.sequence"] = sequence
            }
            return acceptance
        }
    }

    func subscribe() throws -> WorldDeltaStream {
        guard subscribers.count < limits.maximumSubscriptions else {
            telemetry.subscriptionRejectionsCounter.increment()
            throw WorldSubscriptionError.subscriptionLimitReached(
                limit: limits.maximumSubscriptions
            )
        }
        let subscriptionID = UUID()
        let capacity = limits.subscriptionBufferCapacity
        return WorldDeltaStream(bufferingPolicy: .bufferingOldest(capacity)) { continuation in
            subscribers[subscriptionID] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.removeSubscriber(subscriptionID)
                }
            }
        }
    }

    fileprivate static func setEventAttributes(on span: any Span, event: WorldEventEnvelope) {
        span.attributes["world.event.id"] = event.eventID.rawValue
        span.attributes["world.event.type"] = event.type.rawValue
        span.attributes["world.source.id"] = event.source.id.rawValue
    }

    private func processingFinished() {
        pendingEventCountStorage -= 1
        telemetry.queueDepthGauge.record(pendingEventCountStorage)
    }

    private func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        var combinedReduction = WorldReduction()
        for reducer in reducers where reducer.eventTypes.contains(event.type) {
            let reduction = try reducer.reduce(event)
            combinedReduction.changedFacts.append(contentsOf: reduction.changedFacts)
            combinedReduction.derivedEvents.append(contentsOf: reduction.derivedEvents)
        }
        return combinedReduction
    }

    private func publish(_ deltas: [WorldDelta]) {
        for delta in deltas {
            publishedDeltaCountStorage += 1
            var terminatedSubscriptions: [UUID] = []
            for (subscriptionID, continuation) in subscribers {
                switch continuation.yield(delta) {
                case .enqueued:
                    break
                case .dropped:
                    telemetry.subscriptionDropsCounter.increment()
                    continuation.finish(
                        throwing: WorldSubscriptionError.fellBehind(
                            bufferCapacity: limits.subscriptionBufferCapacity
                        )
                    )
                    terminatedSubscriptions.append(subscriptionID)
                case .terminated:
                    terminatedSubscriptions.append(subscriptionID)
                @unknown default:
                    terminatedSubscriptions.append(subscriptionID)
                }
            }
            for subscriptionID in terminatedSubscriptions {
                subscribers.removeValue(forKey: subscriptionID)
            }
        }
    }

    private func removeSubscriber(_ subscriptionID: UUID) {
        subscribers.removeValue(forKey: subscriptionID)
    }
}

private struct ProcessedWorldEvent: Sendable {
    let event: WorldEventEnvelope
    let changedFacts: [Fact]
}

private struct WorldEventProcessor: Sendable {
    let eventStore: any WorldEventStore
    let factStore: any WorldFactStore
    let clock: any WorldClock
    let maximumDerivedEvents: Int
    let telemetry: WorldTelemetry

    func process(
        _ rootEvent: WorldEventEnvelope,
        reduce: @escaping @Sendable (WorldEventEnvelope) async throws -> WorldReduction,
        publish: @escaping @Sendable ([WorldDelta]) async -> Void
    ) async throws -> WorldEventAcceptance {
        do {
            var pendingEvents = [rootEvent]
            var nextEventIndex = 0
            var derivedEventCount = 0
            var rootAcceptance: WorldEventAcceptance?
            var processedEvents: [ProcessedWorldEvent] = []

            while nextEventIndex < pendingEvents.count {
                let proposedEvent = pendingEvents[nextEventIndex]
                nextEventIndex += 1
                let receivedAt = await clock.now
                let appendResult = try await eventStore.append(
                    proposedEvent, receivedAt: receivedAt)
                let acceptance = WorldEventAcceptance(appendResult)
                if rootAcceptance == nil {
                    rootAcceptance = acceptance
                    record(disposition: acceptance.disposition)
                }

                let acceptedEvent = acceptance.event
                if acceptance.disposition != .accepted,
                    try await eventStore.isProcessed(eventID: acceptedEvent.eventID)
                {
                    continue
                }

                let reduction = try await withSpan("world.event.process") { span in
                    World.setEventAttributes(on: span, event: acceptedEvent)
                    if let sequence = acceptedEvent.worldSequence {
                        span.attributes["world.sequence"] = sequence
                    }
                    if let acceptedAt = acceptedEvent.receivedAt {
                        let lag = max(
                            0,
                            acceptedAt.timeIntervalSince(acceptedEvent.occurredAt) * 1_000
                        )
                        span.attributes["world.event_lag_ms"] = lag
                        telemetry.eventLagTimer.recordMilliseconds(Int64(lag.rounded()))
                    }
                    let reduction = try await reduce(acceptedEvent)
                    for fact in reduction.changedFacts {
                        try await factStore.save(fact)
                    }
                    return reduction
                }
                derivedEventCount += reduction.derivedEvents.count
                guard derivedEventCount <= maximumDerivedEvents else {
                    throw WorldProcessingError.derivedEventLimitExceeded(
                        limit: maximumDerivedEvents
                    )
                }
                pendingEvents.append(
                    contentsOf: reduction.derivedEvents.map {
                        $0.caused(by: acceptedEvent.eventID)
                    }
                )
                processedEvents.append(
                    ProcessedWorldEvent(
                        event: acceptedEvent,
                        changedFacts: reduction.changedFacts
                    )
                )
            }

            guard let rootAcceptance else {
                throw WorldProcessingError.missingRootAcceptance
            }

            // Deltas are at-least-once. Publishing before the completion markers prevents a
            // partial marker write from permanently hiding an already-produced descendant delta.
            await publish(
                processedEvents.map {
                    WorldDelta(event: $0.event, changedFacts: $0.changedFacts)
                }
            )

            // Mark descendants first. If a write fails, retrying the still-unmarked root safely
            // regenerates the batch while already-complete descendants remain idempotent.
            let processedAt = await clock.now
            for processedEvent in processedEvents.reversed() {
                try await eventStore.markProcessed(
                    eventID: processedEvent.event.eventID,
                    processedAt: processedAt
                )
            }
            telemetry.processedCounter.increment(by: processedEvents.count)
            return rootAcceptance
        } catch {
            telemetry.processingFailuresCounter.increment()
            throw error
        }
    }

    private func record(disposition: WorldEventDisposition) {
        switch disposition {
        case .accepted:
            telemetry.acceptedCounter.increment()
        case .duplicateEvent:
            telemetry.duplicateEventCounter.increment()
        case .duplicateSourceEvent:
            telemetry.duplicateSourceEventCounter.increment()
        }
    }
}

private struct WorldTelemetry: Sendable {
    let receivedCounter = Counter(label: "creature_world.events.received")
    let acceptedCounter = Counter(label: "creature_world.events.accepted")
    let rejectedCounter = Counter(label: "creature_world.events.rejected")
    let duplicateEventCounter = Counter(
        label: "creature_world.events.duplicate",
        dimensions: [("reason", "event_id")]
    )
    let duplicateSourceEventCounter = Counter(
        label: "creature_world.events.duplicate",
        dimensions: [("reason", "source_event_id")]
    )
    let processedCounter = Counter(label: "creature_world.events.processed")
    let processingFailuresCounter = Counter(label: "creature_world.events.processing_failures")
    let subscriptionRejectionsCounter = Counter(label: "creature_world.subscriptions.rejected")
    let subscriptionDropsCounter = Counter(label: "creature_world.subscriptions.dropped")
    let queueDepthGauge = Gauge(label: "creature_world.queue.depth")
    let eventLagTimer = Metrics.Timer(label: "creature_world.event.lag")
}

extension WorldEventAcceptance {
    fileprivate init(_ result: EventAppendResult) {
        switch result {
        case .inserted(let event):
            self.init(disposition: .accepted, event: event)
        case .duplicateEvent(let event):
            self.init(disposition: .duplicateEvent, event: event)
        case .duplicateSourceEvent(let event):
            self.init(disposition: .duplicateSourceEvent, event: event)
        }
    }
}

extension WorldEventEnvelope {
    fileprivate func caused(by eventID: EventID) -> WorldEventEnvelope {
        var event = self
        let cause = ProvenanceReference.event(eventID)
        if !event.causedBy.contains(cause) {
            event.causedBy.append(cause)
        }
        return event
    }
}

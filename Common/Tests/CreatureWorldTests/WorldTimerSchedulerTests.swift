import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

@Suite("Durable World timers")
struct WorldTimerSchedulerTests {
    @Test("Startup recovery fires an overdue timer once without sleeping")
    func overdueTimerFiresOnceAfterRecovery() async throws {
        let dueAt = Date(timeIntervalSince1970: 1_000)
        let clock = ManualWorldClock(now: dueAt.addingTimeInterval(12))
        let timer = try makeTimer(dueAt: dueAt)
        let store = TestTimerStore(timers: [timer])
        let sink = DeduplicatingTimerEventSink()

        let firstScheduler = makeScheduler(store: store, sink: sink, clock: clock)
        try await firstScheduler.recover()
        #expect(await sink.uniqueEvents.count == 1)
        #expect(await store.timer(timer.timerID)?.status == .fired)

        let restartedScheduler = makeScheduler(store: store, sink: sink, clock: clock)
        try await restartedScheduler.recover()
        #expect(await sink.uniqueEvents.count == 1)
        #expect(await sink.acceptAttemptCount == 1)
    }

    @Test("Advancing the manual clock fires a future timer without a test sleep")
    func futureTimerUsesInjectedClock() async throws {
        let start = Date(timeIntervalSince1970: 1_500)
        let clock = ManualWorldClock(now: start)
        let timer = try makeTimer(dueAt: start.addingTimeInterval(10))
        let store = TestTimerStore()
        let sink = DeduplicatingTimerEventSink()
        let scheduler = WorldTimerScheduler(
            store: store,
            eventSink: sink,
            clock: clock,
            logger: Logger(label: "world-timer-tests")
        )

        try await scheduler.schedule(timer)
        while await clock.pendingSleepCount == 0 {
            await Task.yield()
        }
        try await clock.advance(by: 10)
        while await store.timer(timer.timerID)?.status != .fired {
            await Task.yield()
        }

        #expect(await store.timer(timer.timerID)?.status == .fired)
        #expect(await sink.uniqueEvents.count == 1)
        await scheduler.shutdown()
    }

    @Test("A transient persistence failure retries through the injected clock")
    func transientFailureRetriesWithoutSleeping() async throws {
        let start = Date(timeIntervalSince1970: 1_750)
        let clock = ManualWorldClock(now: start)
        let timer = try makeTimer(dueAt: start.addingTimeInterval(10))
        let store = TestTimerStore(failedClaimAttempts: 1)
        let sink = DeduplicatingTimerEventSink()
        let scheduler = WorldTimerScheduler(
            store: store,
            eventSink: sink,
            clock: clock,
            logger: Logger(label: "world-timer-tests")
        )

        try await scheduler.schedule(timer)
        while await clock.pendingSleepCount == 0 {
            await Task.yield()
        }
        try await clock.advance(by: 10)
        while true {
            let claimAttemptCount = await store.claimAttemptCount
            let pendingSleepCount = await clock.pendingSleepCount
            if claimAttemptCount > 0, pendingSleepCount > 0 {
                break
            }
            await Task.yield()
        }
        try await clock.advance(by: 5)
        while await store.timer(timer.timerID)?.status != .fired {
            await Task.yield()
        }

        #expect(await store.claimAttemptCount == 2)
        #expect(await sink.uniqueEvents.count == 1)
        await scheduler.shutdown()
    }

    @Test("A completion race during recovery keeps the world up and the timer durable")
    func firingStateSurvivesRestart() async throws {
        let dueAt = Date(timeIntervalSince1970: 2_000)
        let clock = ManualWorldClock(now: dueAt.addingTimeInterval(3))
        let timer = try makeTimer(dueAt: dueAt)
        let store = TestTimerStore(timers: [timer], failedMarkAttempts: 1)
        let firstWorld = World(eventStore: store, factStore: store, reducers: [], clock: clock)

        let firstScheduler = WorldTimerScheduler(
            store: store,
            eventSink: firstWorld,
            clock: clock,
            logger: Logger(label: "world-timer-tests"),
            automaticallyWaits: false
        )
        // Recovery completes despite the lost completion race: the connection stays usable, the
        // timer remains claimed and durable, and the fired event was accepted exactly once.
        try await firstScheduler.recover()
        #expect(await store.timer(timer.timerID)?.status == .firing)
        #expect(await store.acceptedEventCount == 1)

        let restartedWorld = World(eventStore: store, factStore: store, reducers: [], clock: clock)
        let restartedScheduler = WorldTimerScheduler(
            store: store,
            eventSink: restartedWorld,
            clock: clock,
            logger: Logger(label: "world-timer-tests"),
            automaticallyWaits: false
        )
        try await restartedScheduler.recover()
        #expect(await store.timer(timer.timerID)?.status == .fired)
        #expect(await store.acceptedEventCount == 1)
        #expect(await store.eventAppendAttemptCount == 2)
    }

    @Test("Rescheduling replaces the stable timer key and cancellation prevents firing")
    func rescheduleAndCancelUseStableKey() async throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let clock = ManualWorldClock(now: start)
        let original = try makeTimer(dueAt: start.addingTimeInterval(10))
        let replacement = try makeTimer(dueAt: start.addingTimeInterval(20))
        let store = TestTimerStore()
        let sink = DeduplicatingTimerEventSink()
        let scheduler = makeScheduler(store: store, sink: sink, clock: clock)

        try await scheduler.schedule(original)
        try await scheduler.schedule(replacement)
        try await clock.advance(by: 10)
        try await scheduler.recover()
        #expect(await sink.uniqueEvents.isEmpty)

        #expect(try await scheduler.cancel(timerID: replacement.timerID))
        try await clock.advance(by: 10)
        try await scheduler.recover()
        #expect(await sink.uniqueEvents.isEmpty)
        #expect(await store.timer(replacement.timerID)?.status == .canceled)
    }

    @Test("Timer-fired event records stable identity, provenance, and lateness")
    func firedEventCarriesSemanticContext() async throws {
        let dueAt = Date(timeIntervalSince1970: 4_000)
        let firingAt = dueAt.addingTimeInterval(2.5)
        let cause = try EventID(validating: "00000000-0000-0000-0000-000000000501")
        let subject = try EntityID(validating: "person:april")
        let timer = try makeTimer(
            dueAt: dueAt,
            subjectIDs: [subject],
            causedBy: [.event(cause)],
            payload: ["reason": .string("departure")]
        )

        let event = try WorldTimerScheduler.firedEvent(for: timer, firingAt: firingAt)

        #expect(event.type == timer.purpose)
        #expect(event.occurredAt == dueAt)
        #expect(event.observedAt == firingAt)
        #expect(event.source.id.rawValue == timer.timerID.rawValue)
        #expect(event.source.kind == "world-timer")
        #expect(event.source.sourceEventID?.contains(timer.timerID.rawValue) == true)
        #expect(event.subjectIDs == [subject])
        #expect(event.causedBy == [.event(cause)])
        #expect(event.payload["reason"] == .string("departure"))
        #expect(event.payload["lateness_ms"] == .number(2_500))
    }

    @Test("Recovery rejects an unbounded active timer set")
    func recoveryIsBounded() async throws {
        let start = Date(timeIntervalSince1970: 5_000)
        let first = try makeTimer(
            timerID: .stable("first:purpose"),
            dueAt: start.addingTimeInterval(10)
        )
        let second = try makeTimer(
            timerID: .stable("second:purpose"),
            dueAt: start.addingTimeInterval(20)
        )
        let scheduler = WorldTimerScheduler(
            store: TestTimerStore(timers: [first, second]),
            eventSink: DeduplicatingTimerEventSink(),
            clock: ManualWorldClock(now: start),
            logger: Logger(label: "world-timer-tests"),
            limits: WorldTimerSchedulerLimits(maximumActiveTimers: 1),
            automaticallyWaits: false
        )

        await #expect(throws: WorldTimerSchedulerError.activeTimerLimitReached(limit: 1)) {
            try await scheduler.recover()
        }
    }

    private func makeScheduler(
        store: TestTimerStore,
        sink: DeduplicatingTimerEventSink,
        clock: ManualWorldClock
    ) -> WorldTimerScheduler {
        WorldTimerScheduler(
            store: store,
            eventSink: sink,
            clock: clock,
            logger: Logger(label: "world-timer-tests"),
            automaticallyWaits: false
        )
    }

    private func makeTimer(
        timerID: TimerID? = nil,
        dueAt: Date,
        subjectIDs: [EntityID] = [],
        causedBy: [ProvenanceReference] = [],
        payload: [String: WorldJSONValue] = [:]
    ) throws -> WorldTimer {
        WorldTimer(
            timerID: try timerID ?? .stable("calendar-event-123:departure-due"),
            purpose: try WorldEventType(validating: "calendar.departure-due"),
            dueAt: dueAt,
            subjectIDs: subjectIDs,
            causedBy: causedBy,
            payload: payload
        )
    }
}

private actor TestTimerStore: WorldTimerStore, WorldEventStore, WorldFactStore {
    private var timers: [TimerID: WorldTimer]
    private var failedClaimAttempts: Int
    private var failedMarkAttempts: Int
    private var eventsByID: [EventID: WorldEventEnvelope] = [:]
    private var eventsBySourceIdentity: [String: WorldEventEnvelope] = [:]
    private var processedEventIDs: Set<EventID> = []
    private var nextSequence: Int64 = 1
    private(set) var eventAppendAttemptCount = 0
    private(set) var claimAttemptCount = 0

    init(
        timers: [WorldTimer] = [],
        failedClaimAttempts: Int = 0,
        failedMarkAttempts: Int = 0
    ) {
        self.timers = Dictionary(uniqueKeysWithValues: timers.map { ($0.timerID, $0) })
        self.failedClaimAttempts = failedClaimAttempts
        self.failedMarkAttempts = failedMarkAttempts
    }

    func schedule(_ timer: WorldTimer) {
        timers[timer.timerID] = timer
    }

    func cancel(timerID: TimerID, canceledAt: Date) -> Bool {
        guard var timer = timers[timerID], timer.status == .pending else { return false }
        timer.status = .canceled
        timer.canceledAt = canceledAt
        timers[timerID] = timer
        return true
    }

    func recoverable(limit: Int) -> [WorldTimer] {
        Array(
            timers.values
                .filter { $0.status == .pending || $0.status == .firing }
                .sorted {
                    if $0.dueAt == $1.dueAt {
                        return $0.timerID.rawValue < $1.timerID.rawValue
                    }
                    return $0.dueAt < $1.dueAt
                }
                .prefix(limit)
        )
    }

    func claim(timerID: TimerID, dueAt: Date, firingAt: Date) throws -> WorldTimer? {
        claimAttemptCount += 1
        if failedClaimAttempts > 0 {
            failedClaimAttempts -= 1
            throw TestTimerStoreError.transient
        }
        guard var timer = timers[timerID], timer.dueAt == dueAt else { return nil }
        guard timer.status == .firing || (timer.status == .pending && timer.dueAt <= firingAt)
        else { return nil }
        timer.status = .firing
        timer.firingAt = firingAt
        timers[timerID] = timer
        return timer
    }

    func markFired(timerID: TimerID, dueAt: Date, firedAt: Date) -> Bool {
        guard var timer = timers[timerID], timer.dueAt == dueAt, timer.status == .firing else {
            return false
        }
        if failedMarkAttempts > 0 {
            failedMarkAttempts -= 1
            return false
        }
        timer.status = .fired
        timer.firedAt = firedAt
        timers[timerID] = timer
        return true
    }

    func timer(_ timerID: TimerID) -> WorldTimer? {
        timers[timerID]
    }

    var acceptedEventCount: Int { eventsByID.count }

    func append(_ event: WorldEventEnvelope, receivedAt: Date) -> EventAppendResult {
        eventAppendAttemptCount += 1
        if let existing = eventsByID[event.eventID] {
            return .duplicateEvent(existing)
        }
        if let sourceEventID = event.source.sourceEventID {
            let sourceIdentity = "\(event.source.id.rawValue):\(sourceEventID)"
            if let existing = eventsBySourceIdentity[sourceIdentity] {
                return .duplicateSourceEvent(existing)
            }
        }

        var accepted = event
        accepted.receivedAt = receivedAt
        accepted.worldSequence = nextSequence
        nextSequence += 1
        eventsByID[accepted.eventID] = accepted
        if let sourceEventID = accepted.source.sourceEventID {
            eventsBySourceIdentity["\(accepted.source.id.rawValue):\(sourceEventID)"] = accepted
        }
        return .inserted(accepted)
    }

    func isProcessed(eventID: EventID) -> Bool {
        processedEventIDs.contains(eventID)
    }

    func markProcessed(eventID: EventID, processedAt _: Date) {
        processedEventIDs.insert(eventID)
    }

    func save(_: Fact) {}
    func supersede(by _: Fact) {}
}

private enum TestTimerStoreError: Error {
    case transient
}

private actor DeduplicatingTimerEventSink: WorldEventSink {
    private(set) var uniqueEvents: [WorldEventEnvelope] = []
    private(set) var acceptAttemptCount = 0
    private var eventsBySourceIdentity: [String: WorldEventEnvelope] = [:]

    func accept(_ event: WorldEventEnvelope) -> WorldEventAcceptance {
        acceptAttemptCount += 1
        let sourceIdentity = "\(event.source.id.rawValue):\(event.source.sourceEventID ?? "")"
        if let existing = eventsBySourceIdentity[sourceIdentity] {
            return WorldEventAcceptance(disposition: .duplicateSourceEvent, event: existing)
        }
        eventsBySourceIdentity[sourceIdentity] = event
        uniqueEvents.append(event)
        return WorldEventAcceptance(disposition: .accepted, event: event)
    }
}

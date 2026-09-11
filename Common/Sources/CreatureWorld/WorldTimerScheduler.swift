import Foundation
import Logging
import Metrics
import Tracing
import WorldCore

struct WorldTimerSchedulerLimits: Equatable, Sendable {
    static let `default` = WorldTimerSchedulerLimits()

    let maximumActiveTimers: Int

    init(maximumActiveTimers: Int = 10_000) {
        precondition(maximumActiveTimers > 0)
        self.maximumActiveTimers = maximumActiveTimers
    }
}

enum WorldTimerSchedulerError: Error, Equatable, LocalizedError, Sendable {
    case activeTimerLimitReached(limit: Int)
    case shutDown

    var errorDescription: String? {
        switch self {
        case .activeTimerLimitReached(let limit):
            "Creature World active timer limit reached (limit: \(limit))"
        case .shutDown:
            "Creature World timer scheduler is shut down"
        }
    }
}

actor WorldTimerScheduler {
    private struct ScheduledTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let store: any WorldTimerStore
    private let eventSink: any WorldEventSink
    private let clock: any WorldClock
    private let logger: Logger
    private let limits: WorldTimerSchedulerLimits
    private let retryInterval: TimeInterval
    private let automaticallyWaits: Bool
    private let telemetry = WorldTimerTelemetry()
    private var scheduledTasks: [TimerID: ScheduledTask] = [:]
    private var activeTimerIDs: Set<TimerID> = []
    private var operationTail: Task<Void, Never>?
    private var isShutDown = false

    init(
        store: any WorldTimerStore,
        eventSink: any WorldEventSink,
        clock: any WorldClock = SystemWorldClock(),
        logger: Logger,
        limits: WorldTimerSchedulerLimits = .default,
        retryInterval: TimeInterval = 5,
        automaticallyWaits: Bool = true
    ) {
        precondition(retryInterval > 0)
        self.store = store
        self.eventSink = eventSink
        self.clock = clock
        self.logger = logger
        self.limits = limits
        self.retryInterval = retryInterval
        self.automaticallyWaits = automaticallyWaits
    }

    func recover() async throws {
        try await enqueue { scheduler in
            try await scheduler.performRecovery()
        }
    }

    func schedule(_ timer: WorldTimer) async throws {
        try await enqueue { scheduler in
            try await scheduler.performSchedule(timer)
        }
    }

    @discardableResult
    func cancel(timerID: TimerID) async throws -> Bool {
        try await enqueue { scheduler in
            try await scheduler.performCancellation(timerID: timerID)
        }
    }

    func shutdown() async {
        isShutDown = true
        for scheduledTask in scheduledTasks.values {
            scheduledTask.task.cancel()
        }
        scheduledTasks.removeAll()
        activeTimerIDs.removeAll()
        await operationTail?.value
        operationTail = nil
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable (isolated WorldTimerScheduler) async throws -> Result
    ) async throws -> Result {
        guard !isShutDown else { throw WorldTimerSchedulerError.shutDown }
        let previous = operationTail
        let work = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self, await self.isRunning else {
                throw WorldTimerSchedulerError.shutDown
            }
            return try await operation(self)
        }
        operationTail = Task {
            _ = try? await work.value
        }
        return try await work.value
    }

    private var isRunning: Bool { !isShutDown }

    private func performRecovery() async throws {
        let recoveryLimit =
            limits.maximumActiveTimers == Int.max ? Int.max : limits.maximumActiveTimers + 1
        let timers = try await store.recoverable(limit: recoveryLimit)
        guard timers.count <= limits.maximumActiveTimers else {
            throw WorldTimerSchedulerError.activeTimerLimitReached(
                limit: limits.maximumActiveTimers
            )
        }
        telemetry.recoveredCounter.increment(by: timers.count)
        activeTimerIDs = Set(timers.map(\.timerID))

        let now = await clock.now
        for timer in timers {
            guard timer.status == .firing || timer.dueAt <= now else {
                installWait(for: timer, until: timer.dueAt)
                continue
            }
            do {
                try await performFire(timer, at: now)
            } catch {
                // One contested or transiently failing timer must not keep the whole world
                // offline. The timer stays durable exactly as it would after a steady-state
                // failure, and the same retry path picks it up again.
                await retryLater(timer, after: error)
            }
        }
    }

    private func retryLater(_ timer: WorldTimer, after error: any Error) async {
        telemetry.failureCounter.increment()
        logger.error(
            "World timer firing failed; it remains durable and will retry",
            metadata: [
                "error.type": "\(String(reflecting: type(of: error)))",
                "world.timer.id": "\(timer.timerID.rawValue)",
            ]
        )
        let retryAt = (await clock.now).addingTimeInterval(retryInterval)
        installWait(for: timer, until: retryAt)
    }

    private func performSchedule(_ timer: WorldTimer) async throws {
        try await withSpan("world.timer.schedule") { span in
            Self.setAttributes(on: span, timer: timer)
            let isNewTimer = !activeTimerIDs.contains(timer.timerID)
            guard !isNewTimer || activeTimerIDs.count < limits.maximumActiveTimers else {
                telemetry.rejectedCounter.increment()
                throw WorldTimerSchedulerError.activeTimerLimitReached(
                    limit: limits.maximumActiveTimers
                )
            }

            var pendingTimer = timer
            pendingTimer.status = .pending
            pendingTimer.firingAt = nil
            pendingTimer.firedAt = nil
            pendingTimer.canceledAt = nil
            try await store.schedule(pendingTimer)
            activeTimerIDs.insert(pendingTimer.timerID)
            telemetry.scheduledCounter.increment()
            installWait(for: pendingTimer, until: pendingTimer.dueAt)
        }
    }

    private func performCancellation(timerID: TimerID) async throws -> Bool {
        try await withSpan("world.timer.cancel") { span in
            span.attributes["world.timer.id"] = timerID.rawValue
            let canceledAt = await clock.now
            let canceled = try await store.cancel(timerID: timerID, canceledAt: canceledAt)
            span.attributes["world.timer.canceled"] = canceled
            if canceled {
                scheduledTasks.removeValue(forKey: timerID)?.task.cancel()
                activeTimerIDs.remove(timerID)
                telemetry.canceledCounter.increment()
            }
            return canceled
        }
    }

    private func installWait(for timer: WorldTimer, until deadline: Date) {
        guard automaticallyWaits, !isShutDown else { return }
        scheduledTasks.removeValue(forKey: timer.timerID)?.task.cancel()
        let token = UUID()
        let clock = self.clock
        let task = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
                try Task.checkCancellation()
                await self?.timerAwoke(timer, token: token)
            } catch is CancellationError {
                await self?.waitFinished(timerID: timer.timerID, token: token)
            } catch {
                await self?.waitFailed(timer, token: token, error: error)
            }
        }
        scheduledTasks[timer.timerID] = ScheduledTask(token: token, task: task)
    }

    private func timerAwoke(_ timer: WorldTimer, token: UUID) async {
        guard scheduledTasks[timer.timerID]?.token == token, !isShutDown else { return }
        do {
            try await enqueue { scheduler in
                try await scheduler.performFire(timer, at: await scheduler.clock.now)
            }
            waitFinished(timerID: timer.timerID, token: token)
        } catch {
            await waitFailed(timer, token: token, error: error)
        }
    }

    private func waitFailed(_ timer: WorldTimer, token: UUID, error: any Error) async {
        guard scheduledTasks[timer.timerID]?.token == token, !isShutDown else { return }
        await retryLater(timer, after: error)
    }

    private func waitFinished(timerID: TimerID, token: UUID) {
        guard scheduledTasks[timerID]?.token == token else { return }
        scheduledTasks.removeValue(forKey: timerID)
    }

    private func performFire(_ timer: WorldTimer, at firingAt: Date) async throws {
        try await withSpan("world.timer.fire") { span in
            Self.setAttributes(on: span, timer: timer)
            let lateness = max(0, firingAt.timeIntervalSince(timer.dueAt))
            span.attributes["world.timer.lateness_ms"] = lateness * 1_000

            guard
                let claimed = try await store.claim(
                    timerID: timer.timerID,
                    dueAt: timer.dueAt,
                    firingAt: firingAt
                )
            else {
                span.attributes["world.timer.disposition"] = "not_claimed"
                return
            }

            let event = try Self.firedEvent(for: claimed, firingAt: firingAt)
            _ = try await eventSink.accept(event)
            guard
                try await store.markFired(
                    timerID: claimed.timerID,
                    dueAt: claimed.dueAt,
                    firedAt: firingAt
                )
            else {
                throw WorldTimerPersistenceError.completionRace(timerID: claimed.timerID)
            }
            span.attributes["world.timer.disposition"] = "fired"
            activeTimerIDs.remove(claimed.timerID)
            telemetry.firedCounter.increment()
        }
    }

    static func firedEvent(
        for timer: WorldTimer,
        firingAt: Date
    ) throws -> WorldEventEnvelope {
        let latenessMilliseconds = max(0, firingAt.timeIntervalSince(timer.dueAt) * 1_000)
        var payload = timer.payload
        payload["timer_id"] = .string(timer.timerID.rawValue)
        payload["scheduled_for"] = .string(WorldJSON.timestamp(timer.dueAt))
        payload["fired_at"] = .string(WorldJSON.timestamp(firingAt))
        payload["lateness_ms"] = .number(latenessMilliseconds)

        return try WorldEventEnvelope(
            type: timer.purpose,
            occurredAt: timer.dueAt,
            observedAt: firingAt,
            source: EventSource(
                id: try SourceID(validating: timer.timerID.rawValue),
                kind: "world-timer",
                sourceEventID: timer.occurrenceKey
            ),
            subjectIDs: timer.subjectIDs,
            epistemic: EpistemicState(type: .scheduled, confidence: 1),
            payload: payload,
            causedBy: timer.causedBy
        )
    }

    private static func setAttributes(on span: any Span, timer: WorldTimer) {
        span.attributes["world.timer.id"] = timer.timerID.rawValue
        span.attributes["world.timer.purpose"] = timer.purpose.rawValue
    }
}

enum WorldTimerPersistenceError: Error, Equatable, Sendable {
    case completionRace(timerID: TimerID)
}

private struct WorldTimerTelemetry: Sendable {
    let scheduledCounter = Counter(label: "creature_world.timers.scheduled")
    let canceledCounter = Counter(label: "creature_world.timers.canceled")
    let firedCounter = Counter(label: "creature_world.timers.fired")
    let recoveredCounter = Counter(label: "creature_world.timers.recovered")
    let rejectedCounter = Counter(label: "creature_world.timers.rejected")
    let failureCounter = Counter(label: "creature_world.timers.failures")
}

extension WorldTimer {
    fileprivate var occurrenceKey: String {
        let dueMilliseconds = Int64((dueAt.timeIntervalSince1970 * 1_000).rounded())
        return "\(timerID.rawValue):\(dueMilliseconds)"
    }
}

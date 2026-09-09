import Foundation

public typealias Instant = Date

public protocol WorldClock: Sendable {
    var now: Instant { get async }
    func sleep(until deadline: Instant) async throws
}

public struct SystemWorldClock: WorldClock {
    public init() {}

    public var now: Instant { get async { Date() } }

    public func sleep(until deadline: Instant) async throws {
        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else { return }
        try await Task.sleep(for: .seconds(interval))
    }
}

public enum ManualWorldClockError: Error, Equatable, Sendable {
    case cannotMoveBackward(current: Instant, requested: Instant)
}

/// A deterministic clock for tests, replay, and controlled simulations.
public actor ManualWorldClock: WorldClock {
    private struct Sleeper {
        let deadline: Instant
        let order: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var current: Instant
    private var nextOrder: UInt64 = 0
    private var sleepers: [UUID: Sleeper] = [:]

    public init(now: Instant) {
        self.current = now
    }

    public var now: Instant { current }

    public var pendingSleepCount: Int { sleepers.count }

    public func sleep(until deadline: Instant) async throws {
        try Task.checkCancellation()
        guard deadline > current else { return }

        let sleeperID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if deadline <= current {
                    continuation.resume()
                } else {
                    let order = nextOrder
                    nextOrder += 1
                    sleepers[sleeperID] = Sleeper(
                        deadline: deadline,
                        order: order,
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            Task { await self.cancelSleep(sleeperID) }
        }
    }

    public func advance(by interval: TimeInterval) throws {
        try advance(to: current.addingTimeInterval(interval))
    }

    public func advance(to requested: Instant) throws {
        guard requested >= current else {
            throw ManualWorldClockError.cannotMoveBackward(
                current: current,
                requested: requested
            )
        }
        current = requested

        let ready =
            sleepers
            .filter { $0.value.deadline <= requested }
            .sorted {
                if $0.value.deadline == $1.value.deadline {
                    return $0.value.order < $1.value.order
                }
                return $0.value.deadline < $1.value.deadline
            }
        for (sleeperID, sleeper) in ready {
            sleepers.removeValue(forKey: sleeperID)
            sleeper.continuation.resume()
        }
    }

    private func cancelSleep(_ sleeperID: UUID) {
        sleepers.removeValue(forKey: sleeperID)?.continuation.resume(
            throwing: CancellationError()
        )
    }
}

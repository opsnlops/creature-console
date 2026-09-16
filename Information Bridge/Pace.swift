import Dispatch
import Foundation
import Synchronization

/// A sleep that keeps time: a dispatch timer with the `.strict` flag, on the wall clock, in an
/// `await`. Timer coalescing cannot stretch it, and a Mac that sleeps through the deadline
/// (a laptop with its lid closed, as the first night proved - nothing runs while it sleeps)
/// fires it on waking rather than after the remaining uptime.
enum Pace {
    /// Waits `seconds`, on the clock. Throws `CancellationError` if the task is cancelled.
    static func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .utility))
        defer { timer.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                let once = Once(continuation)
                timer.setEventHandler { once.resume() }
                timer.setCancelHandler { once.resume(throwing: CancellationError()) }
                // On the wall clock: a Mac that sleeps through the deadline fires the timer the
                // moment it wakes, not five minutes of uptime later.
                timer.schedule(wallDeadline: .now() + seconds, leeway: .seconds(1))
                timer.activate()
            }
        } onCancel: {
            timer.cancel()
        }
    }

    static func sleep(for duration: Duration) async throws {
        let (seconds, attoseconds) = duration.components
        try await sleep(seconds: Double(seconds) + Double(attoseconds) / 1e18)
    }

    /// A continuation resumed at most once, whichever handler fires first.
    private final class Once: Sendable {
        private let continuation: Mutex<CheckedContinuation<Void, Error>?>

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = Mutex(continuation)
        }

        func resume() {
            continuation.withLock { taken in
                taken?.resume()
                taken = nil
            }
        }

        func resume(throwing error: Error) {
            continuation.withLock { taken in
                taken?.resume(throwing: error)
                taken = nil
            }
        }
    }
}

import Dispatch
import Foundation
import Synchronization

/// A sleep that keeps time. `Task.sleep` on an idle Mac with its display off is stretched by
/// timer coalescing - the first night's five-minute heartbeat arrived every ten - and no
/// activity assertion changes that. A dispatch timer with the `.strict` flag is the documented
/// way to say the interval matters; this wraps one in an `await`.
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
                timer.schedule(deadline: .now() + seconds, leeway: .seconds(1))
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

#if canImport(os)
    import os

    typealias CreatureLock<Value> = OSAllocatedUnfairLock<Value>
#else
    import Foundation

    /// Cross-platform lock wrapper used when OSAllocatedUnfairLock is unavailable (e.g. on Linux).
    final class CreatureLock<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(initialState: Value) {
            self.value = initialState
        }

        func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
            lock.lock()
            defer { lock.unlock() }
            return try body(&value)
        }
    }
#endif

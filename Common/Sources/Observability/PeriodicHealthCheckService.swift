import ServiceLifecycle

/// Runs an asynchronous health operation on a fixed cadence until graceful shutdown.
///
/// The first check occurs after one interval. Callers that need an eager initial check should
/// perform it before adding this service to their service group.
package struct PeriodicHealthCheckService: Service, Sendable {
    package typealias Operation = @Sendable () async -> Void
    package typealias ShutdownOperation = @Sendable () async -> Void
    package typealias Sleep = @Sendable (Duration) async throws -> Void

    private let interval: Duration
    private let operation: Operation
    private let shutdownOperation: ShutdownOperation
    private let sleep: Sleep

    package init(
        interval: Duration,
        operation: @escaping Operation,
        shutdown: @escaping ShutdownOperation = {},
        sleep: @escaping Sleep = { interval in
            try await Task.sleep(for: interval)
        }
    ) {
        precondition(interval > .zero)
        self.interval = interval
        self.operation = operation
        self.shutdownOperation = shutdown
        self.sleep = sleep
    }

    package func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                while !Task.isCancelled {
                    try await sleep(interval)
                    guard !Task.isCancelled else { break }
                    await operation()
                }
            }
        } catch is CancellationError {
            // Graceful shutdown cancels an in-progress interval sleep.
        } catch {
            await shutdownOperation()
            throw error
        }
        await shutdownOperation()
    }
}

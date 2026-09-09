import Testing

@testable import Observability

@Suite("Periodic health check service")
struct PeriodicHealthCheckServiceTests {
    @Test("Waits before each check and shuts down after cancellation")
    func cadenceAndCancellation() async throws {
        let probe = PeriodicServiceProbe()
        let service = PeriodicHealthCheckService(
            interval: .seconds(5),
            operation: {
                await probe.recordCheck()
            },
            shutdown: {
                await probe.recordShutdown()
            },
            sleep: { interval in
                try await probe.sleep(for: interval)
            }
        )

        try await service.run()

        #expect(await probe.intervals == [.seconds(5), .seconds(5)])
        #expect(await probe.checkCount == 1)
        #expect(await probe.shutdownCount == 1)
    }

    @Test("Runs shutdown cleanup before propagating a scheduler failure")
    func schedulerFailureRunsCleanup() async {
        let probe = PeriodicServiceProbe(sleepError: .schedulerFailed)
        let service = PeriodicHealthCheckService(
            interval: .seconds(1),
            operation: {
                await probe.recordCheck()
            },
            shutdown: {
                await probe.recordShutdown()
            },
            sleep: { interval in
                try await probe.sleep(for: interval)
            }
        )

        await #expect(throws: PeriodicServiceTestError.schedulerFailed) {
            try await service.run()
        }
        #expect(await probe.checkCount == 0)
        #expect(await probe.shutdownCount == 1)
    }
}

private enum PeriodicServiceTestError: Error {
    case schedulerFailed
}

private actor PeriodicServiceProbe {
    private let sleepError: PeriodicServiceTestError?
    private(set) var intervals: [Duration] = []
    private(set) var checkCount = 0
    private(set) var shutdownCount = 0

    init(sleepError: PeriodicServiceTestError? = nil) {
        self.sleepError = sleepError
    }

    func sleep(for interval: Duration) throws {
        intervals.append(interval)
        if let sleepError {
            throw sleepError
        }
        if intervals.count > 1 {
            throw CancellationError()
        }
    }

    func recordCheck() {
        checkCount += 1
    }

    func recordShutdown() {
        shutdownCount += 1
    }
}

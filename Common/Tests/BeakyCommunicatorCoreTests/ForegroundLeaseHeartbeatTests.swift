import BeakyCommunicatorCore
import Foundation
import Testing
import WorldCore

@Suite("Communicator foreground heartbeat")
struct ForegroundLeaseHeartbeatTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let installation = CommunicatorInstallationID(
        rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    )
    private let session = ForegroundSessionID(
        rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )

    @Test("Foreground acquires immediately and background releases immediately")
    func lifecycleTransitions() async {
        let transport = RecordingLeaseTransport()
        let heartbeat = makeHeartbeat(transport: transport)

        await heartbeat.setForeground(true)
        #expect(await heartbeat.isForeground)
        #expect(await transport.operations == [.acquire(installation, session)])

        await heartbeat.setForeground(false)
        #expect(await !heartbeat.isForeground)
        #expect(
            await transport.operations
                == [.acquire(installation, session), .release(installation, session)]
        )
    }

    @Test("Active clients renew every configured heartbeat interval")
    func renewalSchedule() async throws {
        let clock = ManualWorldClock(now: now)
        let transport = RecordingLeaseTransport()
        let heartbeat = makeHeartbeat(transport: transport, clock: clock)
        await heartbeat.setForeground(true)
        await waitForSleeper(on: clock)

        try await clock.advance(by: 29)
        await Task.yield()
        #expect(await transport.operations.count == 1)

        try await clock.advance(by: 1)
        await waitForOperationCount(2, on: transport)
        #expect(
            await transport.operations
                == [.acquire(installation, session), .renew(installation, session)]
        )
        await heartbeat.stop()
    }

    @Test("A failed heartbeat is retried without abandoning foreground state")
    func renewalRetry() async throws {
        let clock = ManualWorldClock(now: now)
        let transport = RecordingLeaseTransport(failedRenewals: 1)
        let heartbeat = makeHeartbeat(transport: transport, clock: clock)
        await heartbeat.setForeground(true)
        await waitForSleeper(on: clock)

        try await clock.advance(by: 30)
        await waitForOperationCount(2, on: transport)
        await waitForSleeper(on: clock)
        try await clock.advance(by: 30)
        await waitForOperationCount(3, on: transport)

        #expect(
            await transport.operations
                == [
                    .acquire(installation, session),
                    .renew(installation, session),
                    .renew(installation, session),
                ]
        )
        #expect(await heartbeat.isForeground)
        await heartbeat.stop()
    }

    @Test("A failed initial acquire is retried as an acquire")
    func acquireRetry() async throws {
        let clock = ManualWorldClock(now: now)
        let transport = RecordingLeaseTransport(failedAcquireAttempts: [1])
        let heartbeat = makeHeartbeat(transport: transport, clock: clock)
        await heartbeat.setForeground(true)
        await waitForSleeper(on: clock)

        try await clock.advance(by: 30)
        await waitForOperationCount(2, on: transport)

        #expect(
            await transport.operations
                == [.acquire(installation, session), .acquire(installation, session)]
        )
        #expect(await heartbeat.isForeground)
        await heartbeat.stop()
    }

    @Test("A missing expired lease is reacquired until the gateway accepts it")
    func expiredLeaseReacquisition() async throws {
        let clock = ManualWorldClock(now: now)
        let transport = RecordingLeaseTransport(
            failedAcquireAttempts: [2],
            renewalResults: [false]
        )
        let heartbeat = makeHeartbeat(transport: transport, clock: clock)
        await heartbeat.setForeground(true)
        await waitForSleeper(on: clock)

        try await clock.advance(by: 30)
        await waitForOperationCount(3, on: transport)
        await waitForSleeper(on: clock)
        try await clock.advance(by: 30)
        await waitForOperationCount(4, on: transport)

        #expect(
            await transport.operations
                == [
                    .acquire(installation, session),
                    .renew(installation, session),
                    .acquire(installation, session),
                    .acquire(installation, session),
                ]
        )
        await heartbeat.stop()
    }

    @Test("Backgrounding closes a delayed-acquire race")
    func delayedAcquireRace() async {
        let transport = DelayedAcquireLeaseTransport()
        let heartbeat = ForegroundLeaseHeartbeat(
            installationID: installation,
            transport: transport,
            sessionFactory: { session }
        )
        let foregroundTransition = Task {
            await heartbeat.setForeground(true)
        }
        while await !transport.acquireIsPending {
            await Task.yield()
        }

        await heartbeat.setForeground(false)
        await transport.completeAcquire()
        await foregroundTransition.value

        #expect(
            await transport.operations
                == [
                    .acquire(installation, session),
                    .release(installation, session),
                    .release(installation, session),
                ]
        )
        #expect(await !heartbeat.isForeground)
    }

    private func makeHeartbeat(
        transport: RecordingLeaseTransport,
        clock: any WorldClock = SystemWorldClock()
    ) -> ForegroundLeaseHeartbeat {
        ForegroundLeaseHeartbeat(
            installationID: installation,
            transport: transport,
            clock: clock,
            sessionFactory: { session }
        )
    }

    private func waitForSleeper(on clock: ManualWorldClock) async {
        while await clock.pendingSleepCount == 0 {
            await Task.yield()
        }
    }

    private func waitForOperationCount(
        _ count: Int,
        on transport: RecordingLeaseTransport
    ) async {
        while await transport.operations.count < count {
            await Task.yield()
        }
    }
}

private enum LeaseOperation: Equatable, Sendable {
    case acquire(CommunicatorInstallationID, ForegroundSessionID)
    case renew(CommunicatorInstallationID, ForegroundSessionID)
    case release(CommunicatorInstallationID, ForegroundSessionID)
}

private enum RecordingLeaseTransportError: Error {
    case unavailable
}

private actor RecordingLeaseTransport: ForegroundLeaseTransport {
    private(set) var operations: [LeaseOperation] = []
    private var acquireAttempt = 0
    private var failedAcquireAttempts: Set<Int>
    private var failedRenewals: Int
    private var renewalResults: [Bool]

    init(
        failedAcquireAttempts: Set<Int> = [],
        failedRenewals: Int = 0,
        renewalResults: [Bool] = []
    ) {
        self.failedAcquireAttempts = failedAcquireAttempts
        self.failedRenewals = failedRenewals
        self.renewalResults = renewalResults
    }

    func acquireForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) throws {
        operations.append(.acquire(installationID, sessionID))
        acquireAttempt += 1
        if failedAcquireAttempts.contains(acquireAttempt) {
            throw RecordingLeaseTransportError.unavailable
        }
    }

    func renewForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) throws -> Bool {
        operations.append(.renew(installationID, sessionID))
        if failedRenewals > 0 {
            failedRenewals -= 1
            throw RecordingLeaseTransportError.unavailable
        }
        return renewalResults.isEmpty ? true : renewalResults.removeFirst()
    }

    func releaseForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) {
        operations.append(.release(installationID, sessionID))
    }
}

private actor DelayedAcquireLeaseTransport: ForegroundLeaseTransport {
    private(set) var operations: [LeaseOperation] = []
    private var acquireContinuation: CheckedContinuation<Void, Never>?

    var acquireIsPending: Bool { acquireContinuation != nil }

    func acquireForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async {
        operations.append(.acquire(installationID, sessionID))
        await withCheckedContinuation { continuation in
            acquireContinuation = continuation
        }
    }

    func renewForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) -> Bool {
        operations.append(.renew(installationID, sessionID))
        return true
    }

    func releaseForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) {
        operations.append(.release(installationID, sessionID))
    }

    func completeAcquire() {
        acquireContinuation?.resume()
        acquireContinuation = nil
    }
}

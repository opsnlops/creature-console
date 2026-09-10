import BeakyCommunicatorCore
import Foundation
import Testing
import WorldCore

@Suite("Communicator foreground leases")
struct ForegroundLeaseTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let installation = CommunicatorInstallationID(
        rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    )
    private let session = ForegroundSessionID(
        rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )

    @Test("Standard timing leaves two missed-heartbeat intervals before expiry")
    func standardTiming() {
        #expect(ForegroundLeaseConfiguration.standard.heartbeatInterval == 30)
        #expect(ForegroundLeaseConfiguration.standard.leaseDuration == 90)
        #expect(ForegroundLeaseConfiguration.standard.maximumActiveLeases == 64)
    }

    @Test("Invalid timing is rejected")
    func invalidTiming() {
        #expect(throws: ForegroundLeaseConfigurationError.nonPositiveHeartbeatInterval) {
            try ForegroundLeaseConfiguration(heartbeatInterval: 0, leaseDuration: 90)
        }
        #expect(throws: ForegroundLeaseConfigurationError.nonPositiveLeaseDuration) {
            try ForegroundLeaseConfiguration(heartbeatInterval: 30, leaseDuration: .infinity)
        }
        #expect(throws: ForegroundLeaseConfigurationError.leaseDoesNotOutliveHeartbeat) {
            try ForegroundLeaseConfiguration(heartbeatInterval: 30, leaseDuration: 30)
        }
        #expect(throws: ForegroundLeaseConfigurationError.nonPositiveMaximumActiveLeases) {
            try ForegroundLeaseConfiguration(
                heartbeatInterval: 30,
                leaseDuration: 90,
                maximumActiveLeases: 0
            )
        }
    }

    @Test("Acquiring a lease makes a foreground client active")
    func acquire() async throws {
        let clock = ManualWorldClock(now: now)
        let registry = ForegroundLeaseRegistry(clock: clock)

        let lease = try await registry.acquire(
            installationID: installation,
            sessionID: session
        )

        #expect(lease.expiresAt == now.addingTimeInterval(90))
        #expect(await registry.hasActiveLease())
        #expect(await registry.activeLeases() == [lease])
    }

    @Test("A heartbeat renews the matching session from the current time")
    func renew() async throws {
        let clock = ManualWorldClock(now: now)
        let registry = ForegroundLeaseRegistry(clock: clock)
        _ = try await registry.acquire(installationID: installation, sessionID: session)
        try await clock.advance(by: 30)

        let renewed = await registry.renew(installationID: installation, sessionID: session)

        #expect(renewed?.expiresAt == now.addingTimeInterval(120))
    }

    @Test("A lease is inactive at its exact expiry boundary")
    func expiryBoundary() async throws {
        let clock = ManualWorldClock(now: now)
        let registry = ForegroundLeaseRegistry(clock: clock)
        _ = try await registry.acquire(installationID: installation, sessionID: session)

        try await clock.advance(by: 89.999)
        #expect(await registry.hasActiveLease())
        try await clock.advance(by: 0.001)
        #expect(await !registry.hasActiveLease())
        #expect(await registry.activeLeases().isEmpty)
    }

    @Test("A delayed release cannot clear a newer foreground session")
    func staleRelease() async throws {
        let clock = ManualWorldClock(now: now)
        let registry = ForegroundLeaseRegistry(clock: clock)
        let newerSession = ForegroundSessionID(
            rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        _ = try await registry.acquire(installationID: installation, sessionID: session)
        let newerLease = try await registry.acquire(
            installationID: installation,
            sessionID: newerSession
        )

        let staleReleaseSucceeded = await registry.release(
            installationID: installation,
            sessionID: session
        )
        #expect(!staleReleaseSucceeded)
        #expect(await registry.activeLeases() == [newerLease])
        let currentReleaseSucceeded = await registry.release(
            installationID: installation,
            sessionID: newerSession
        )
        #expect(currentReleaseSucceeded)
        #expect(await !registry.hasActiveLease())
    }

    @Test("Any active installation suppresses redundant notification delivery")
    func multipleInstallations() async throws {
        let clock = ManualWorldClock(now: now)
        let registry = ForegroundLeaseRegistry(clock: clock)
        let mac = CommunicatorInstallationID(
            rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        )
        let macSession = ForegroundSessionID(
            rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        _ = try await registry.acquire(installationID: installation, sessionID: session)
        try await clock.advance(by: 60)
        _ = try await registry.acquire(installationID: mac, sessionID: macSession)
        try await clock.advance(by: 30)

        #expect(await registry.hasActiveLease())
        #expect(await registry.activeLeases().map(\.installationID) == [mac])
    }

    @Test("The registry bounds active installation state")
    func activeLeaseCapacity() async throws {
        let configuration = try ForegroundLeaseConfiguration(
            heartbeatInterval: 30,
            leaseDuration: 90,
            maximumActiveLeases: 1
        )
        let registry = ForegroundLeaseRegistry(
            clock: ManualWorldClock(now: now),
            configuration: configuration
        )
        _ = try await registry.acquire(installationID: installation, sessionID: session)
        let otherInstallation = CommunicatorInstallationID.generated()

        await #expect(
            throws: ForegroundLeaseRegistryError.capacityExceeded(maximumActiveLeases: 1)
        ) {
            try await registry.acquire(
                installationID: otherInstallation,
                sessionID: .generated()
            )
        }
        #expect(await registry.activeLeases().map(\.installationID) == [installation])
    }

    @Test("Lease JSON uses the shared snake-case wire convention")
    func jsonContract() throws {
        let lease = ForegroundLease(
            installationID: installation,
            sessionID: session,
            expiresAt: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(lease)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(
            object["installation_id"] as? String
                == installation.rawValue.uuidString.lowercased()
        )
        #expect(object["session_id"] as? String == session.rawValue.uuidString.lowercased())
        #expect(object["expires_at"] != nil)
        #expect(object["installationID"] == nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(ForegroundLease.self, from: data) == lease)
    }

    @Test("Malformed wire identifiers are rejected")
    func invalidWireIdentifiers() {
        let data = Data(
            #"{"installation_id":"not-a-uuid","session_id":"also-invalid"}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ForegroundLeaseCommand.self, from: data)
        }
    }
}

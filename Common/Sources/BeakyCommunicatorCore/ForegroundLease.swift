import Foundation
import WorldCore

public enum ForegroundLeaseConfigurationError: Error, Equatable, Sendable {
    case nonPositiveHeartbeatInterval
    case nonPositiveLeaseDuration
    case leaseDoesNotOutliveHeartbeat
    case nonPositiveMaximumActiveLeases
}

public enum ForegroundLeaseRegistryError: Error, Equatable, Sendable {
    case capacityExceeded(maximumActiveLeases: Int)
}

public struct ForegroundLeaseConfiguration: Equatable, Sendable {
    public static let standard = ForegroundLeaseConfiguration(
        validatedHeartbeatInterval: 30,
        leaseDuration: 90,
        maximumActiveLeases: 64
    )

    public var heartbeatInterval: TimeInterval
    public var leaseDuration: TimeInterval
    public var maximumActiveLeases: Int

    public init(
        heartbeatInterval: TimeInterval,
        leaseDuration: TimeInterval,
        maximumActiveLeases: Int = 64
    ) throws {
        guard heartbeatInterval.isFinite, heartbeatInterval > 0 else {
            throw ForegroundLeaseConfigurationError.nonPositiveHeartbeatInterval
        }
        guard leaseDuration.isFinite, leaseDuration > 0 else {
            throw ForegroundLeaseConfigurationError.nonPositiveLeaseDuration
        }
        guard leaseDuration > heartbeatInterval else {
            throw ForegroundLeaseConfigurationError.leaseDoesNotOutliveHeartbeat
        }
        guard maximumActiveLeases > 0 else {
            throw ForegroundLeaseConfigurationError.nonPositiveMaximumActiveLeases
        }
        self.heartbeatInterval = heartbeatInterval
        self.leaseDuration = leaseDuration
        self.maximumActiveLeases = maximumActiveLeases
    }

    private init(
        validatedHeartbeatInterval: TimeInterval,
        leaseDuration: TimeInterval,
        maximumActiveLeases: Int
    ) {
        heartbeatInterval = validatedHeartbeatInterval
        self.leaseDuration = leaseDuration
        self.maximumActiveLeases = maximumActiveLeases
    }
}

public struct CommunicatorInstallationID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public static func generated() -> Self {
        Self(rawValue: UUID())
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ForegroundSessionID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public static func generated() -> Self {
        Self(rawValue: UUID())
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ForegroundLease: Equatable, Sendable, Codable {
    public var installationID: CommunicatorInstallationID
    public var sessionID: ForegroundSessionID
    public var expiresAt: Date

    public init(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID,
        expiresAt: Date
    ) {
        self.installationID = installationID
        self.sessionID = sessionID
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case sessionID = "session_id"
        case expiresAt = "expires_at"
    }
}

public protocol ForegroundLeaseTransport: Sendable {
    func acquireForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws
    func renewForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws -> Bool
    func releaseForegroundLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws
}

/// Drives the client half of the foreground lease without depending on SwiftUI or a transport.
///
/// Lifecycle adapters call `setForeground` using platform-native attention semantics. Failed
/// heartbeats are retried at the next interval, and lease expiry remains the ultimate authority if
/// a suspended or disconnected app cannot deliver its release.
public actor ForegroundLeaseHeartbeat {
    public typealias SessionFactory = @Sendable () -> ForegroundSessionID

    private let installationID: CommunicatorInstallationID
    private let transport: any ForegroundLeaseTransport
    private let clock: any WorldClock
    private let configuration: ForegroundLeaseConfiguration
    private let sessionFactory: SessionFactory
    private var sessionID: ForegroundSessionID?
    private var heartbeatTask: Task<Void, Never>?

    public init(
        installationID: CommunicatorInstallationID,
        transport: any ForegroundLeaseTransport,
        clock: any WorldClock = SystemWorldClock(),
        configuration: ForegroundLeaseConfiguration = .standard,
        sessionFactory: @escaping SessionFactory = { .generated() }
    ) {
        self.installationID = installationID
        self.transport = transport
        self.clock = clock
        self.configuration = configuration
        self.sessionFactory = sessionFactory
    }

    public var isForeground: Bool { sessionID != nil }

    public func setForeground(_ foreground: Bool) async {
        if foreground {
            await beginForegroundSessionIfNeeded()
        } else {
            await endForegroundSessionIfNeeded()
        }
    }

    public func stop() async {
        await endForegroundSessionIfNeeded()
    }

    private func beginForegroundSessionIfNeeded() async {
        guard sessionID == nil else { return }
        let newSessionID = sessionFactory()
        sessionID = newSessionID
        let acquired: Bool
        do {
            try await transport.acquireForegroundLease(
                installationID: installationID,
                sessionID: newSessionID
            )
            acquired = true
        } catch {
            acquired = false
        }

        guard sessionID == newSessionID else {
            // The lifecycle changed while acquire was in flight. A second release closes the race
            // where the first release reached the gateway before the delayed acquire.
            try? await transport.releaseForegroundLease(
                installationID: installationID,
                sessionID: newSessionID
            )
            return
        }
        startHeartbeat(for: newSessionID, acquired: acquired)
    }

    private func endForegroundSessionIfNeeded() async {
        guard let endingSessionID = sessionID else { return }
        sessionID = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        try? await transport.releaseForegroundLease(
            installationID: installationID,
            sessionID: endingSessionID
        )
    }

    private func startHeartbeat(for activeSessionID: ForegroundSessionID, acquired: Bool) {
        heartbeatTask?.cancel()
        let clock = self.clock
        let heartbeatInterval = configuration.heartbeatInterval
        heartbeatTask = Task { [weak self] in
            var needsAcquire = !acquired
            while !Task.isCancelled {
                let deadline = await clock.now.addingTimeInterval(heartbeatInterval)
                do {
                    try await clock.sleep(until: deadline)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                needsAcquire = await self.maintain(activeSessionID, needsAcquire: needsAcquire)
            }
        }
    }

    private func maintain(
        _ activeSessionID: ForegroundSessionID,
        needsAcquire: Bool
    ) async -> Bool {
        guard sessionID == activeSessionID else { return needsAcquire }
        if needsAcquire {
            do {
                try await transport.acquireForegroundLease(
                    installationID: installationID,
                    sessionID: activeSessionID
                )
                return false
            } catch {
                return true
            }
        }

        let renewed: Bool
        do {
            renewed = try await transport.renewForegroundLease(
                installationID: installationID,
                sessionID: activeSessionID
            )
        } catch {
            return false
        }
        guard !renewed else { return false }
        do {
            try await transport.acquireForegroundLease(
                installationID: installationID,
                sessionID: activeSessionID
            )
            return false
        } catch {
            return true
        }
    }
}

/// Gateway-side authority for short-lived, per-installation foreground leases.
///
/// A session identifier makes release idempotent and prevents a delayed release from an older
/// foreground session from clearing a newer session on the same installation.
public actor ForegroundLeaseRegistry {
    private let clock: any WorldClock
    private let configuration: ForegroundLeaseConfiguration
    private var leases: [CommunicatorInstallationID: ForegroundLease] = [:]

    public init(
        clock: any WorldClock = SystemWorldClock(),
        configuration: ForegroundLeaseConfiguration = .standard
    ) {
        self.clock = clock
        self.configuration = configuration
    }

    @discardableResult
    public func acquire(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async throws -> ForegroundLease {
        let now = await clock.now
        discardExpiredLeases(at: now)
        guard
            leases[installationID] != nil
                || leases.count < configuration.maximumActiveLeases
        else {
            throw ForegroundLeaseRegistryError.capacityExceeded(
                maximumActiveLeases: configuration.maximumActiveLeases
            )
        }
        let lease = makeLease(
            installationID: installationID,
            sessionID: sessionID,
            at: now
        )
        leases[installationID] = lease
        return lease
    }

    @discardableResult
    public func renew(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) async -> ForegroundLease? {
        let now = await clock.now
        discardExpiredLeases(at: now)
        guard leases[installationID]?.sessionID == sessionID else { return nil }
        let lease = makeLease(installationID: installationID, sessionID: sessionID, at: now)
        leases[installationID] = lease
        return lease
    }

    @discardableResult
    public func release(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID
    ) -> Bool {
        guard leases[installationID]?.sessionID == sessionID else { return false }
        leases.removeValue(forKey: installationID)
        return true
    }

    public func hasActiveLease() async -> Bool {
        discardExpiredLeases(at: await clock.now)
        return !leases.isEmpty
    }

    public func activeLeases() async -> [ForegroundLease] {
        discardExpiredLeases(at: await clock.now)
        return leases.values.sorted {
            $0.installationID.rawValue.uuidString < $1.installationID.rawValue.uuidString
        }
    }

    private func discardExpiredLeases(at now: Date) {
        leases = leases.filter { $0.value.expiresAt > now }
    }

    private func makeLease(
        installationID: CommunicatorInstallationID,
        sessionID: ForegroundSessionID,
        at now: Date
    ) -> ForegroundLease {
        ForegroundLease(
            installationID: installationID,
            sessionID: sessionID,
            expiresAt: now.addingTimeInterval(configuration.leaseDuration)
        )
    }
}

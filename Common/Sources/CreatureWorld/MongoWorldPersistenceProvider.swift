import Foundation
import Logging
import Observability
import ServiceLifecycle
import WorldCore

struct MongoWorldPersistenceConnection: Sendable {
    let isHealthy: @Sendable () async -> Bool
    let recoverTimers: @Sendable () async throws -> Void
    let scheduleTimer: @Sendable (WorldTimer) async throws -> Void
    let cancelTimer: @Sendable (TimerID) async throws -> Bool
    let shutdown: @Sendable () async -> Void

    init(
        persistence: MongoWorldPersistence,
        clock: any WorldClock = SystemWorldClock(),
        logger: Logger
    ) {
        let world = World(
            eventStore: persistence.events,
            factStore: persistence.facts,
            reducers: [],
            clock: clock
        )
        let timerScheduler = WorldTimerScheduler(
            store: persistence.timers,
            eventSink: world,
            clock: clock,
            logger: logger
        )
        isHealthy = { await persistence.isHealthy() }
        recoverTimers = { try await timerScheduler.recover() }
        scheduleTimer = { try await timerScheduler.schedule($0) }
        cancelTimer = { try await timerScheduler.cancel(timerID: $0) }
        shutdown = {
            await timerScheduler.shutdown()
            await persistence.cluster.disconnect()
        }
    }

    init(
        isHealthy: @escaping @Sendable () async -> Bool,
        recoverTimers: @escaping @Sendable () async throws -> Void = {},
        scheduleTimer: @escaping @Sendable (WorldTimer) async throws -> Void = { _ in },
        cancelTimer: @escaping @Sendable (TimerID) async throws -> Bool = { _ in false },
        shutdown: @escaping @Sendable () async -> Void
    ) {
        self.isHealthy = isHealthy
        self.recoverTimers = recoverTimers
        self.scheduleTimer = scheduleTimer
        self.cancelTimer = cancelTimer
        self.shutdown = shutdown
    }
}

actor MongoWorldPersistenceProvider {
    typealias Connector = @Sendable (String, Logger) async throws -> MongoWorldPersistenceConnection

    private let connector: Connector
    private let logger: Logger
    private let uri: String
    private var consecutiveFailures = 0
    private var isConnecting = false
    private var connection: MongoWorldPersistenceConnection?

    init(
        uri: String,
        logger: Logger,
        connector: @escaping Connector = { uri, logger in
            let persistence = try await MongoWorldPersistence.connect(to: uri, logger: logger)
            return MongoWorldPersistenceConnection(
                persistence: persistence,
                logger: logger
            )
        }
    ) {
        self.uri = uri
        self.logger = logger
        self.connector = connector
    }

    func connectIfNeeded() async {
        guard connection == nil, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            let candidate = try await connector(uri, logger)
            do {
                try await candidate.recoverTimers()
            } catch {
                await candidate.shutdown()
                throw error
            }
            connection = candidate
            if consecutiveFailures > 0 {
                logger.info(
                    "MongoDB connection recovered",
                    metadata: ["mongodb.retry_attempts": "\(consecutiveFailures)"]
                )
            }
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
            let metadata: Logger.Metadata = [
                "error": "\(error.localizedDescription)",
                "mongodb.retry_attempt": "\(consecutiveFailures)",
            ]
            if consecutiveFailures == 1 {
                logger.warning(
                    "MongoDB is unavailable; Creature World will continue starting and retry",
                    metadata: metadata
                )
            } else {
                logger.debug("MongoDB retry failed", metadata: metadata)
            }
        }
    }

    func isHealthy() async -> Bool {
        guard let connection else { return false }
        guard await connection.isHealthy() else {
            logger.warning("MongoDB health check failed; persistence is unavailable")
            await connection.shutdown()
            self.connection = nil
            return false
        }
        return true
    }

    func shutdown() async {
        await connection?.shutdown()
        connection = nil
    }

    func schedule(_ timer: WorldTimer) async throws {
        guard let connection else { throw MongoWorldPersistenceProviderError.unavailable }
        try await connection.scheduleTimer(timer)
    }

    func cancel(timerID: TimerID) async throws -> Bool {
        guard let connection else { throw MongoWorldPersistenceProviderError.unavailable }
        return try await connection.cancelTimer(timerID)
    }
}

enum MongoWorldPersistenceProviderError: Error, Equatable, Sendable {
    case unavailable
}

struct MongoWorldPersistenceService: Service, Sendable {
    let provider: MongoWorldPersistenceProvider
    var retryInterval: Duration = .seconds(5)

    func run() async throws {
        try await PeriodicHealthCheckService(
            interval: retryInterval,
            operation: {
                await provider.connectIfNeeded()
                _ = await provider.isHealthy()
            },
            shutdown: {
                await provider.shutdown()
            }
        ).run()
    }
}

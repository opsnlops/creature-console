import Foundation
import Logging
import Observability
import ServiceLifecycle
import WorldCore

struct MongoWorldPersistenceConnection: Sendable {
    let acceptEvent: @Sendable (WorldEventEnvelope) async throws -> WorldEventAcceptance
    let events: @Sendable (Int64, Int) async throws -> WorldEventPage
    let currentFacts: @Sendable (EntityID?, FactID?, Int) async throws -> WorldFactPage
    let timers: @Sendable (WorldTimerStatus?, TimerID?, Int) async throws -> WorldTimerPage
    let snapshot: @Sendable (Int) async throws -> WorldSnapshot
    let subscribe: @Sendable () async throws -> WorldDeltaStream
    let finishSubscriptions: @Sendable () async -> Void
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
        acceptEvent = { try await world.accept($0) }
        events = { sequence, limit in
            let loaded = try await persistence.events.events(
                after: sequence,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageEvents = Array(loaded.prefix(limit))
            return WorldEventPage(
                events: pageEvents,
                nextSequence: pageEvents.last?.worldSequence ?? sequence,
                hasMore: hasMore
            )
        }
        currentFacts = { subjectID, after, limit in
            let loaded = try await persistence.facts.currentFacts(
                subjectID: subjectID,
                after: after,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageFacts = Array(loaded.prefix(limit))
            return WorldFactPage(
                facts: pageFacts,
                nextFactID: pageFacts.last?.factID,
                hasMore: hasMore
            )
        }
        timers = { status, after, limit in
            let loaded = try await persistence.timers.timers(
                status: status,
                after: after,
                limit: limit + 1
            )
            let hasMore = loaded.count > limit
            let pageTimers = Array(loaded.prefix(limit))
            return WorldTimerPage(
                timers: pageTimers,
                nextTimerID: pageTimers.last?.timerID,
                hasMore: hasMore
            )
        }
        snapshot = { limit in
            let latestSequence = try await persistence.events.latestSequence()
            let loadedFacts = try await persistence.facts.currentFacts(
                subjectID: nil,
                after: nil,
                limit: limit + 1
            )
            let loadedTimers = try await persistence.timers.timers(limit: limit + 1)
            return WorldSnapshot(
                latestSequence: latestSequence,
                facts: Array(loadedFacts.prefix(limit)),
                timers: Array(loadedTimers.prefix(limit)),
                factsTruncated: loadedFacts.count > limit,
                timersTruncated: loadedTimers.count > limit
            )
        }
        subscribe = { try await world.subscribe() }
        finishSubscriptions = { await world.finishSubscriptions() }
        isHealthy = { await persistence.isHealthy() }
        recoverTimers = { try await timerScheduler.recover() }
        scheduleTimer = { try await timerScheduler.schedule($0) }
        cancelTimer = { try await timerScheduler.cancel(timerID: $0) }
        shutdown = {
            await world.closeSubscriptions(error: WorldAPIError.databaseUnavailable)
            await timerScheduler.shutdown()
            await persistence.cluster.disconnect()
        }
    }

    init(
        acceptEvent: @escaping @Sendable (WorldEventEnvelope) async throws -> WorldEventAcceptance =
            {
                _ in throw WorldAPIError.databaseUnavailable
            },
        events: @escaping @Sendable (Int64, Int) async throws -> WorldEventPage = {
            _, _ in throw WorldAPIError.databaseUnavailable
        },
        currentFacts: @escaping @Sendable (EntityID?, FactID?, Int) async throws -> WorldFactPage =
            {
                _, _, _ in throw WorldAPIError.databaseUnavailable
            },
        timers:
            @escaping @Sendable (WorldTimerStatus?, TimerID?, Int) async throws -> WorldTimerPage =
            {
                _, _, _ in throw WorldAPIError.databaseUnavailable
            },
        snapshot: @escaping @Sendable (Int) async throws -> WorldSnapshot = {
            _ in throw WorldAPIError.databaseUnavailable
        },
        subscribe: @escaping @Sendable () async throws -> WorldDeltaStream = {
            throw WorldAPIError.databaseUnavailable
        },
        finishSubscriptions: @escaping @Sendable () async -> Void = {},
        isHealthy: @escaping @Sendable () async -> Bool,
        recoverTimers: @escaping @Sendable () async throws -> Void = {},
        scheduleTimer: @escaping @Sendable (WorldTimer) async throws -> Void = { _ in },
        cancelTimer: @escaping @Sendable (TimerID) async throws -> Bool = { _ in false },
        shutdown: @escaping @Sendable () async -> Void
    ) {
        self.acceptEvent = acceptEvent
        self.events = events
        self.currentFacts = currentFacts
        self.timers = timers
        self.snapshot = snapshot
        self.subscribe = subscribe
        self.finishSubscriptions = finishSubscriptions
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

    func accept(_ event: WorldEventEnvelope) async throws -> WorldEventAcceptance {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.acceptEvent(event)
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.events(sequence, limit)
    }

    func currentFacts(subjectID: EntityID?, after: FactID?, limit: Int) async throws
        -> WorldFactPage
    {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.currentFacts(subjectID, after, limit)
    }

    func timers(status: WorldTimerStatus?, after: TimerID?, limit: Int) async throws
        -> WorldTimerPage
    {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.timers(status, after, limit)
    }

    func snapshot(limit: Int) async throws -> WorldSnapshot {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.snapshot(limit)
    }

    func subscribe() async throws -> WorldDeltaStream {
        guard let connection else { throw WorldAPIError.databaseUnavailable }
        return try await connection.subscribe()
    }

    func finishSubscriptions() async {
        await connection?.finishSubscriptions()
    }
}

extension MongoWorldPersistenceProvider: WorldApplicationService {}

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

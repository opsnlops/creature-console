import Foundation
import Logging
import ServiceLifecycle

struct MongoWorldPersistenceConnection: Sendable {
    let isHealthy: @Sendable () async -> Bool
    let shutdown: @Sendable () async -> Void

    init(persistence: MongoWorldPersistence) {
        isHealthy = { await persistence.isHealthy() }
        shutdown = { await persistence.cluster.disconnect() }
    }

    init(
        isHealthy: @escaping @Sendable () async -> Bool,
        shutdown: @escaping @Sendable () async -> Void
    ) {
        self.isHealthy = isHealthy
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
            return MongoWorldPersistenceConnection(persistence: persistence)
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
            connection = try await connector(uri, logger)
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
}

struct MongoWorldPersistenceService: Service, Sendable {
    let provider: MongoWorldPersistenceProvider
    var retryInterval: Duration = .seconds(5)

    func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                while !Task.isCancelled {
                    try await Task.sleep(for: retryInterval)
                    await provider.connectIfNeeded()
                    _ = await provider.isHealthy()
                }
            }
        } catch is CancellationError {
            // Graceful shutdown cancels the retry loop's sleep.
        }
        await provider.shutdown()
    }
}

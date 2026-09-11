import Foundation
import Logging
import MongoKitten

enum MongoWorldStartupError: Error, Equatable, LocalizedError, Sendable {
    case connectionFailed(targets: String, database: String, reason: String)
    case migrationFailed(database: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let targets, let database, let reason):
            "Creature World could not connect to MongoDB at \(targets), database \(database): "
                + "\(reason). Verify MongoDB is running and check MONGODB_URI or --mongodb-uri."
        case .migrationFailed(let database, let reason):
            "Creature World connected to MongoDB but could not prepare database \(database): "
                + reason
        }
    }
}

struct MongoWorldConnectionDetails: Equatable, Sendable {
    let targets: String
    let database: String
    let usesTLS: Bool

    init(settings: ConnectionSettings) {
        self.targets = settings.hosts
            .map { "\($0.hostname):\($0.port)" }
            .joined(separator: ",")
        self.database = settings.targetDatabase ?? "none"
        self.usesTLS = settings.useSSL
    }

    var logMetadata: Logger.Metadata {
        [
            "mongodb.database": "\(database)",
            "mongodb.targets": "\(targets)",
            "mongodb.tls": "\(usesTLS)",
        ]
    }
}

struct MongoWorldPersistence: Sendable {
    let cluster: MongoCluster
    let database: MongoDatabase
    let events: WorldEventRepository
    let facts: FactRepository
    let timers: WorldTimerRepository
    let sourceCheckpoints: SourceCheckpointRepository
    let conversations: MongoConversationRepository
    let characterDeliveries: MongoCharacterDeliveryRepository

    static func connect(to uri: String, logger: Logger) async throws -> MongoWorldPersistence {
        let settings = try ConnectionSettings(uri)
        let connectionDetails = MongoWorldConnectionDetails(settings: settings)
        logger.info("Connecting to MongoDB", metadata: connectionDetails.logMetadata)

        let cluster: MongoCluster
        do {
            cluster = try await MongoCluster(connectingTo: settings, logger: logger)
        } catch {
            logger.error(
                "Unable to connect to MongoDB",
                metadata: connectionDetails.logMetadata.merging([
                    "error": "\(String(describing: error))"
                ]) { _, new in new }
            )
            throw MongoWorldStartupError.connectionFailed(
                targets: connectionDetails.targets,
                database: connectionDetails.database,
                reason: String(describing: error)
            )
        }
        logger.debug("MongoDB connection created", metadata: connectionDetails.logMetadata)

        guard let databaseName = settings.targetDatabase else {
            await cluster.disconnect()
            throw CreatureWorldConfigurationError.invalidMongoURI
        }
        let database = cluster[databaseName]
        guard database.name == CreatureWorldConfiguration.databaseName else {
            await cluster.disconnect()
            throw CreatureWorldConfigurationError.unexpectedMongoDatabase(
                expected: CreatureWorldConfiguration.databaseName,
                actual: database.name
            )
        }

        do {
            logger.info(
                "Preparing MongoDB schema",
                metadata: [
                    "mongodb.database": "\(database.name)",
                    "mongodb.migration_version": "\(MongoWorldMigrator.currentVersion)",
                ]
            )
            try await MongoWorldMigrator(database: database, logger: logger).migrate()
            logger.info(
                "Creature World MongoDB persistence is ready",
                metadata: [
                    "mongodb.database": "\(database.name)",
                    "mongodb.migration_version": "\(MongoWorldMigrator.currentVersion)",
                ]
            )
            return MongoWorldPersistence(
                cluster: cluster,
                database: database,
                events: WorldEventRepository(database: database),
                facts: FactRepository(database: database),
                timers: WorldTimerRepository(database: database),
                sourceCheckpoints: SourceCheckpointRepository(database: database),
                conversations: MongoConversationRepository(database: database),
                characterDeliveries: MongoCharacterDeliveryRepository(database: database)
            )
        } catch {
            logger.error(
                "Unable to prepare MongoDB schema",
                metadata: [
                    "error": "\(String(describing: error))",
                    "mongodb.database": "\(database.name)",
                ]
            )
            await cluster.disconnect()
            throw MongoWorldStartupError.migrationFailed(
                database: database.name,
                reason: String(describing: error)
            )
        }
    }

    func isHealthy() async -> Bool {
        do {
            return try await database[MongoWorldCollection.schemaMigrations]
                .findOne(["_id": MongoWorldMigrator.currentVersion]) != nil
        } catch {
            return false
        }
    }
}

enum MongoWorldCollection {
    static let events = "world_events"
    static let eventProcessing = "world_event_processing"
    static let facts = "facts"
    static let timers = "timers"
    static let sourceCheckpoints = "source_checkpoints"
    static let schemaMigrations = "schema_migrations"
    static let counters = "world_counters"
    static let utteranceIngresses = "utterance_ingresses"
    static let conversationItems = "conversation_items"
    static let characterDeliveries = "character_deliveries"
}

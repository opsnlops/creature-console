import Foundation
import Logging
import MongoKitten
import ServiceLifecycle

struct MongoWorldPersistence: Sendable {
    let cluster: MongoCluster
    let database: MongoDatabase
    let events: WorldEventRepository
    let facts: FactRepository
    let timers: WorldTimerRepository
    let sourceCheckpoints: SourceCheckpointRepository

    static func connect(to uri: String, logger: Logger) async throws -> MongoWorldPersistence {
        let settings = try ConnectionSettings(uri)
        let cluster = try await MongoCluster(connectingTo: settings, logger: logger)
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
            try await MongoWorldMigrator(database: database).migrate()
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
                sourceCheckpoints: SourceCheckpointRepository(database: database)
            )
        } catch {
            await cluster.disconnect()
            throw error
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

struct MongoWorldPersistenceService: Service, Sendable {
    let cluster: MongoCluster

    func run() async throws {
        try await gracefulShutdown()
        await cluster.disconnect()
    }
}

enum MongoWorldCollection {
    static let events = "world_events"
    static let facts = "facts"
    static let timers = "timers"
    static let sourceCheckpoints = "source_checkpoints"
    static let schemaMigrations = "schema_migrations"
    static let counters = "world_counters"
}

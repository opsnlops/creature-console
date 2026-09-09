import Logging

struct CreatureWorldDependencies: Sendable {
    let configuration: CreatureWorldConfiguration
    let buildInfo: CreatureWorldBuildInfo
    let logger: Logger
    let healthService: HealthService
    let persistence: MongoWorldPersistenceProvider?

    static func live(
        configuration: CreatureWorldConfiguration,
        logger: Logger,
        buildInfo: CreatureWorldBuildInfo = .current
    ) async throws -> CreatureWorldDependencies {
        let persistence = MongoWorldPersistenceProvider(
            uri: configuration.mongoURI,
            logger: logger
        )
        await persistence.connectIfNeeded()
        return CreatureWorldDependencies(
            configuration: configuration,
            buildInfo: buildInfo,
            logger: logger,
            healthService: HealthService(
                buildInfo: buildInfo,
                readinessCheck: { await persistence.isHealthy() }
            ),
            persistence: persistence
        )
    }

    static func testing(
        configuration: CreatureWorldConfiguration,
        logger: Logger,
        buildInfo: CreatureWorldBuildInfo,
        readinessCheck: @escaping @Sendable () async -> Bool = { true }
    ) -> CreatureWorldDependencies {
        CreatureWorldDependencies(
            configuration: configuration,
            buildInfo: buildInfo,
            logger: logger,
            healthService: HealthService(
                buildInfo: buildInfo,
                readinessCheck: readinessCheck
            ),
            persistence: nil
        )
    }
}

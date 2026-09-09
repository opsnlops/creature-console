import Logging

struct CreatureWorldDependencies: Sendable {
    let configuration: CreatureWorldConfiguration
    let buildInfo: CreatureWorldBuildInfo
    let logger: Logger
    let healthService: HealthService
    let persistence: MongoWorldPersistence?

    static func live(
        configuration: CreatureWorldConfiguration,
        logger: Logger,
        buildInfo: CreatureWorldBuildInfo = .current
    ) async throws -> CreatureWorldDependencies {
        let persistence = try await MongoWorldPersistence.connect(
            to: configuration.mongoURI,
            logger: logger
        )
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
        buildInfo: CreatureWorldBuildInfo
    ) -> CreatureWorldDependencies {
        CreatureWorldDependencies(
            configuration: configuration,
            buildInfo: buildInfo,
            logger: logger,
            healthService: HealthService(buildInfo: buildInfo),
            persistence: nil
        )
    }
}

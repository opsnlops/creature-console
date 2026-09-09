import Logging

struct CreatureWorldDependencies: Sendable {
    let configuration: CreatureWorldConfiguration
    let buildInfo: CreatureWorldBuildInfo
    let logger: Logger
    let healthService: HealthService

    static func live(
        configuration: CreatureWorldConfiguration,
        logger: Logger,
        buildInfo: CreatureWorldBuildInfo = .current
    ) -> CreatureWorldDependencies {
        CreatureWorldDependencies(
            configuration: configuration,
            buildInfo: buildInfo,
            logger: logger,
            healthService: HealthService(buildInfo: buildInfo)
        )
    }
}

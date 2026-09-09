import Logging
import ServiceLifecycle

struct CreatureWorldLifecycleReporter: Service, Sendable {
    let buildInfo: CreatureWorldBuildInfo
    let logger: Logger

    func run() async throws {
        logger.info(
            "Creature World version \(buildInfo.version)",
            metadata: [
                "build.version": "\(buildInfo.version)",
                "world.schema_version": "\(buildInfo.schemaVersion)",
            ]
        )
        try await gracefulShutdown()
        logger.info("Creature World shutdown complete")
    }
}

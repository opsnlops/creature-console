import Logging
import ServiceLifecycle

struct CreatureWorldLifecycleReporter: Service, Sendable {
    let logger: Logger

    func run() async throws {
        try await gracefulShutdown()
        logger.info("Creature World shutdown complete")
    }
}

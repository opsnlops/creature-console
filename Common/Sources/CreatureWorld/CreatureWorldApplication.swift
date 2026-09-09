import Hummingbird
import ServiceLifecycle

func makeCreatureWorldApplication(
    dependencies: CreatureWorldDependencies,
    services: [any Service] = []
) -> Application<RouterResponder<BasicRequestContext>> {
    let router = Router(context: BasicRequestContext.self)
    router.addMiddleware {
        LogRequestsMiddleware(.debug)
    }
    router.get("v1/health") { _, _ in
        dependencies.healthService.response()
    }

    let lifecycleReporter = CreatureWorldLifecycleReporter(
        buildInfo: dependencies.buildInfo,
        logger: dependencies.logger
    )

    return Application(
        router: router,
        configuration: .init(
            address: .hostname(
                dependencies.configuration.host,
                port: dependencies.configuration.port
            ),
            serverName: "creature-world"
        ),
        services: services + [lifecycleReporter],
        onServerRunning: { _ in
            dependencies.logger.info(
                "Creature World is listening",
                metadata: [
                    "build.version": "\(dependencies.buildInfo.version)",
                    "http.host": "\(dependencies.configuration.host)",
                    "http.port": "\(dependencies.configuration.port)",
                    "world.schema_version": "\(dependencies.buildInfo.schemaVersion)",
                ]
            )
        },
        logger: dependencies.logger
    )
}

extension HealthResponse: ResponseEncodable {}

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
        let health = await dependencies.healthService.response()
        return EditedResponse(
            status: health.status == "ok" ? .ok : .serviceUnavailable,
            response: health
        )
    }

    let lifecycleReporter = CreatureWorldLifecycleReporter(logger: dependencies.logger)
    let persistenceServices: [any Service] =
        dependencies.persistence.map {
            [MongoWorldPersistenceService(provider: $0)]
        } ?? []

    return Application(
        router: router,
        configuration: .init(
            address: .hostname(
                dependencies.configuration.host,
                port: dependencies.configuration.port
            ),
            serverName: "creature-world"
        ),
        services: services + persistenceServices + [lifecycleReporter],
        onServerRunning: { _ in
            dependencies.logger.info(
                "Creature World is listening",
                metadata: [
                    "build.version": "\(dependencies.buildInfo.version)",
                    "http.host": "\(dependencies.configuration.host)",
                    "http.port": "\(dependencies.configuration.port)",
                    "mongodb.database": "\(CreatureWorldConfiguration.databaseName)",
                    "world.schema_version": "\(dependencies.buildInfo.schemaVersion)",
                ]
            )
        },
        logger: dependencies.logger
    )
}

extension HealthResponse: ResponseEncodable {}

import Logging

struct CreatureWorldDependencies: Sendable {
    let configuration: CreatureWorldConfiguration
    let buildInfo: CreatureWorldBuildInfo
    let logger: Logger
    let healthService: HealthService
    let persistence: MongoWorldPersistenceProvider?
    let worldService: any WorldApplicationService
    let conversationService: any ConversationApplicationService
    let characterSessionService: any CharacterSessionApplicationService

    static func live(
        configuration: CreatureWorldConfiguration,
        logger: Logger,
        buildInfo: CreatureWorldBuildInfo = .current
    ) async throws -> CreatureWorldDependencies {
        let persistence = MongoWorldPersistenceProvider(
            uri: configuration.mongoURI,
            presence: configuration.presence,
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
            persistence: persistence,
            worldService: persistence,
            conversationService: persistence,
            characterSessionService: persistence
        )
    }

    static func testing(
        configuration: CreatureWorldConfiguration,
        logger: Logger,
        buildInfo: CreatureWorldBuildInfo,
        readinessCheck: @escaping @Sendable () async -> Bool = { true },
        worldService: any WorldApplicationService = UnavailableWorldApplicationService(),
        conversationService: any ConversationApplicationService =
            UnavailableConversationApplicationService(),
        characterSessionService: any CharacterSessionApplicationService =
            UnavailableCharacterSessionApplicationService()
    ) -> CreatureWorldDependencies {
        CreatureWorldDependencies(
            configuration: configuration,
            buildInfo: buildInfo,
            logger: logger,
            healthService: HealthService(
                buildInfo: buildInfo,
                readinessCheck: readinessCheck
            ),
            persistence: nil,
            worldService: worldService,
            conversationService: conversationService,
            characterSessionService: characterSessionService
        )
    }
}

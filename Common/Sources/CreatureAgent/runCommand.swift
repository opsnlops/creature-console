import ArgumentParser
import AsyncHTTPClient
import Common
import Foundation
import Logging
import Observability
import ServiceLifecycle
import WorldCore

extension CreatureAgent {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Listen to MQTT and trigger ad-hoc speech"
        )

        @Option(
            name: .long,
            help: "Path to the YAML configuration file (see sample_agent_config.yaml)")
        var configPath: String

        @Option(name: .long, help: "MQTT broker host override")
        var mqttHost: String?

        @Option(name: .long, help: "MQTT broker port override")
        var mqttPort: Int?

        @Option(
            name: .long,
            help: "Log level (trace, debug, info, notice, warning, error, critical)")
        var logLevel: LogLevelOption = .info

        @Flag(
            name: [.customShort("d"), .long],
            help: "Enable debug logging (overrides --log-level)")
        var debug: Bool = false

        @Flag(
            name: .long,
            help: "Log OpenAI response bodies for debugging")
        var traceOpenAI: Bool = false

        @Flag(
            name: .customLong("trace-openai"),
            help: "Alias for --trace-open-ai")
        var traceOpenAICompat: Bool = false

        @OptionGroup()
        var globalOptions: GlobalOptions

        mutating func run() async throws {
            let otelServices = try bootstrapObservability(serviceName: "creature-agent")

            let loggerLevel =
                (debug || traceOpenAI || traceOpenAICompat)
                ? Logger.Level.debug
                : logLevel.level
            var configuredLogger = Logger(label: "io.opsnlops.creature-agent")
            configuredLogger.logLevel = loggerLevel
            let logger = configuredLogger

            let config = try AgentConfig.load(from: URL(fileURLWithPath: configPath))
            let traceResponses = traceOpenAI || traceOpenAICompat

            if config.mode == .world {
                try await runWorldMode(
                    config: config,
                    globalOptions: globalOptions,
                    logger: logger,
                    traceResponses: traceResponses,
                    observabilityServices: otelServices
                )
                return
            }

            let mqttHostValue = mqttHost ?? config.mqttHost
            let mqttPortValue = mqttPort ?? config.mqttPort

            let areaConfigs = config.areas
            let topicMap = Dictionary(
                uniqueKeysWithValues: areaConfigs.flatMap { area in
                    area.items.map {
                        (
                            $0.topic,
                            TopicConfigMap(
                                area: area.area,
                                cooldownSeconds: area.cooldownTimeSeconds,
                                prompt: $0.agentPrompt
                            )
                        )
                    }
                }
            )

            logger.info("Loaded config for creature \(config.creatureId)")
            logger.info(
                "MQTT target \(mqttHostValue):\(mqttPortValue) (topics: \(topicMap.count))")
            logger.debug("LLM backend: \(config.llmBackend)")
            logger.debug("LLM model \(config.llmModel)")
            logger.debug("LLM temperature \(config.llmTemperature)")

            let respondToPrompt: @Sendable (String) async throws -> String
            var respondToPromptStreaming: (@Sendable (String) -> AsyncStream<String>)?

            switch config.llmBackend {
            case .openai:
                guard let apiKey = config.llmApiKey else {
                    reportError("llmApiKey is required when using the openai backend")
                    throw ExitCode.failure
                }
                let openAI = OpenAIClient(
                    apiKey: apiKey,
                    model: config.llmModel,
                    systemPrompt: config.llmSystemPrompt,
                    temperature: config.llmTemperature,
                    reasoningEffort: config.llmReasoningEffort,
                    logger: logger,
                    traceResponses: traceResponses
                )
                respondToPrompt = { try await openAI.respond(to: $0) }
                respondToPromptStreaming = nil  // OpenAI streaming not implemented yet

            case .local:
                let localLLM = LocalLLMClient(
                    host: config.localLlmHost,
                    port: config.localLlmPort,
                    model: config.llmModel,
                    systemPrompt: config.llmSystemPrompt,
                    temperature: config.llmTemperature,
                    maxTokens: config.localLlmMaxTokens,
                    minSentenceChars: config.minSentenceChars,
                    conversationHistorySize: config.conversationHistorySize,
                    logger: logger,
                    traceResponses: traceResponses
                )
                respondToPrompt = { try await localLLM.respond(to: $0) }
                respondToPromptStreaming = { localLLM.respondStreaming(to: $0) }
            }

            let server = getServer(config: globalOptions)

            do {
                let creatureLookup = try await server.getCreature(creatureId: config.creatureId)
                switch creatureLookup {
                case .success:
                    break
                case .failure(let error):
                    try await reportCreatureLookupFailure(
                        error: error,
                        creatureId: config.creatureId,
                        host: server.serverHostname,
                        port: server.serverPort
                    )
                }
            } catch {
                try await reportCreatureLookupFailure(
                    error: error,
                    creatureId: config.creatureId,
                    host: server.serverHostname,
                    port: server.serverPort
                )
            }

            let eventTracker = MQTTEventTracker(logger: logger)

            let processor = AgentEventProcessor(
                topicMap: topicMap,
                eventTracker: eventTracker,
                creatureId: config.creatureId,
                fallbackSpeech: config.fallbackSpeech,
                llmBackend: config.llmBackend,
                llmModel: config.llmModel,
                respondToPrompt: respondToPrompt,
                respondToPromptStreaming: respondToPromptStreaming,
                createSpeech: { creatureId, text in
                    await server.createAdHocSpeechAnimation(
                        creatureId: creatureId,
                        text: text,
                        resumePlaylist: true
                    )
                },
                server: server,
                logger: logger
            )

            let listener = MQTTAgentListener(
                host: mqttHostValue,
                port: mqttPortValue,
                topics: Array(topicMap.keys),
                reconnectBackoff: config.mqttReconnectBackoff,
                logLevel: loggerLevel,
                maxConcurrentTasks: config.maxConcurrentTasks
            )

            try await listener.connect { topic, payload, isRetained in
                await processor.processEvent(
                    topic: topic, payload: payload, isRetained: isRetained)
            }

            let agentService = AgentService(listener: listener, logger: logger)

            var services: [any Service] = otelServices + [agentService]
            if config.llmBackend == .local {
                let healthCheck = LocalLLMHealthCheck(
                    host: config.localLlmHost,
                    port: config.localLlmPort,
                    intervalSeconds: 120,
                    logger: logger
                )
                services.append(healthCheck)
            }

            let serviceGroup = ServiceGroup(
                services: services,
                gracefulShutdownSignals: [.sigterm],
                cancellationSignals: [.sigint],
                logger: Logger(label: "creature-agent")
            )
            try await serviceGroup.run()
        }
    }
}

struct AgentService: Service {
    let listener: MQTTAgentListener
    let logger: Logger

    func run() async throws {
        try await gracefulShutdown()
        logger.info("Shutting down creature-agent")
        await listener.shutdown()
    }
}

enum LogLevelOption: String, ExpressibleByArgument {
    case trace, debug, info, notice, warning, error, critical

    var level: Logger.Level {
        switch self {
        case .trace:
            return .trace
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .notice
        case .warning:
            return .warning
        case .error:
            return .error
        case .critical:
            return .critical
        }
    }
}

@MainActor
private func reportCreatureLookupFailure(
    error: Error,
    creatureId: CreatureIdentifier,
    host: String,
    port: Int
) throws -> Never {
    let message: String
    message =
        "Failed to find creature \(creatureId) on \(host):\(port): \(ServerError.detailedMessage(from: error))"
    reportError(message)
    throw ExitCode.failure
}

private func reportError(_ message: String) {
    if let data = "\(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - World-resident mode

enum WorldModeError: Error, LocalizedError {
    case missingAPIKey
    case invalidEntityID(String)
    case personaUnreadable(String, any Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "llmBackend: openai needs OPENAI_API_KEY in the environment (/etc/default/creature-agent-<instance>) or llmApiKey in the config"
        case .personaUnreadable(let path, let error):
            "personaPath \(path) could not be loaded: \(error)"
        case .invalidEntityID(let value):
            "Invalid world entity identifier in configuration: \(value)"
        }
    }
}

/// Runs the agent as a resident of Creature World: follow the conversation, think with the
/// local model, answer through the world's delivery router. Nothing here touches MQTT.
private func runWorldMode(
    config: AgentConfig,
    globalOptions: GlobalOptions,
    logger: Logger,
    traceResponses: Bool,
    observabilityServices: [any Service]
) async throws {
    let world = config.world
    guard let characterID = EntityID(rawValue: world.characterEntityID) else {
        throw WorldModeError.invalidEntityID(world.characterEntityID)
    }
    guard let personID = EntityID(rawValue: world.personEntityID) else {
        throw WorldModeError.invalidEntityID(world.personEntityID)
    }
    guard let regionID = EntityID(rawValue: world.regionEntityID) else {
        throw WorldModeError.invalidEntityID(world.regionEntityID)
    }
    // Who this mind is: April's persona file when there is one, else the prompt as before.
    let persona: CharacterPersona
    if let personaPath = world.personaPath {
        do {
            persona = .structured(try Persona.load(from: URL(fileURLWithPath: personaPath)))
        } catch {
            throw WorldModeError.personaUnreadable(personaPath, error)
        }
    } else {
        persona = .text(config.llmSystemPrompt)
    }
    logger.info(
        "Persona loaded",
        metadata: [
            "agent.persona_version": "\(persona.versionTag)",
            "agent.persona_path": "\(world.personaPath ?? "(llmSystemPrompt)")",
        ])

    logger.info(
        "Beaky's mind is waking up in Creature World",
        metadata: [
            "world.url": "\(world.worldURL.absoluteString)",
            "agent.character_id": "\(characterID.rawValue)",
            "agent.person_id": "\(personID.rawValue)",
            "agent.state_directory": "\(world.stateDirectory)",
            "llm.model": "\(config.llmModel)",
            "agent.prompt_version": "\(CharacterMind.promptVersion)",
            "agent.stage": "\(world.stage.rawValue)",
            "creature.id": "\(config.creatureId)",
            "world.region_id": "\(regionID.rawValue)",
        ]
    )

    // The model behind this mind. Nemo on the LAN, or OpenAI so one bird can be compared
    // against the local model live; either way the mind sees sentences as they are composed.
    let respond: CharacterMind.Respond
    let respondStreaming: CharacterMind.RespondStreaming
    switch config.llmBackend {
    case .local:
        let localLLM = LocalLLMClient(
            host: config.localLlmHost,
            port: config.localLlmPort,
            model: config.llmModel,
            systemPrompt: config.llmSystemPrompt,
            temperature: config.llmTemperature,
            maxTokens: config.localLlmMaxTokens,
            minSentenceChars: config.minSentenceChars,
            conversationHistorySize: config.conversationHistorySize,
            logger: logger,
            traceResponses: traceResponses
        )
        respond = { try await localLLM.respond(messages: $0) }
        respondStreaming = { localLLM.respondStreaming(messages: $0, recordingHistoryFor: nil) }
    case .openai:
        // The key comes from the environment (`/etc/default/creature-agent-<instance>`) or
        // the config file; never from the persona.
        guard
            let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? config.llmApiKey,
            !apiKey.isEmpty
        else { throw WorldModeError.missingAPIKey }
        let openAI = OpenAIClient(
            apiKey: apiKey,
            model: config.llmModel,
            systemPrompt: config.llmSystemPrompt,
            temperature: config.llmTemperature,
            reasoningEffort: config.llmReasoningEffort,
            minSentenceChars: config.minSentenceChars,
            logger: logger,
            traceResponses: traceResponses
        )
        respond = { try await openAI.respond(messages: $0) }
        respondStreaming = { openAI.respondStreaming(messages: $0) }
    }
    logger.info(
        "Model chosen",
        metadata: [
            "llm.backend": "\(config.llmBackend.rawValue)", "llm.model": "\(config.llmModel)",
            "llm.reasoning_effort": "\(config.llmReasoningEffort ?? "none")",
        ])
    var clientConfiguration = HTTPClient.Configuration()
    clientConfiguration.timeout = .init(connect: .seconds(10), read: .seconds(120))
    let client = HTTPClient(
        eventLoopGroupProvider: .singleton,
        configuration: clientConfiguration,
        backgroundActivityLogger: logger
    )
    let cursor = WorldAgentCursor(
        stateDirectory: URL(fileURLWithPath: world.stateDirectory, isDirectory: true),
        worldURL: world.worldURL,
        logger: logger
    )
    let responder = WorldResponder(client: client, worldURL: world.worldURL, logger: logger)
    // This process is one mind for one character in one region; the world holds it to that.
    let session = WorldCharacterSession(
        client: responder,
        characterID: characterID,
        regionID: regionID,
        instance: CharacterMindInstance(
            host: ProcessInfo.processInfo.hostName,
            processID: Int(ProcessInfo.processInfo.processIdentifier),
            creatureID: config.creatureId,
            version: CreatureAgent.configuration.version,
            pronouns: persona.pronouns
        ),
        logger: logger
    )
    // The room is Creature Server, reached exactly as the MQTT agent reaches it.
    let stage: CharacterMind.Stage? =
        switch world.stage {
        case .physical:
            CharacterMind.Stage(
                stager: responder,
                room: CreatureServerSpeechStage(
                    server: getServer(config: globalOptions),
                    creatureID: config.creatureId,
                    logger: logger
                ),
                respondStreaming: respondStreaming,
                session: { await session.sessionID }
            )
        case .communicatorOnly:
            nil
        }
    let mind = CharacterMind(
        configuration: CharacterMind.Configuration(
            persona: persona,
            characterID: characterID,
            personID: personID,
            maximumReplyAge: world.maximumReplyAge,
            maximumContextTurns: world.maximumContextTurns,
            modelTimeout: .seconds(world.llmTimeout),
            modelName: config.llmModel,
            timeZone: world.timeZone
        ),
        respond: respond,
        stage: stage,
        logger: logger
    )
    let mindService = WorldMindService(
        subscriber: WorldPerceptSubscriber(
            worldURL: world.worldURL,
            characterID: characterID,
            cursor: cursor,
            logger: logger
        ),
        mind: mind,
        responder: responder,
        session: session,
        client: client,
        logger: logger
    )
    let healthCheck = LocalLLMHealthCheck(
        host: config.localLlmHost,
        port: config.localLlmPort,
        intervalSeconds: 120,
        logger: logger
    )

    let serviceGroup = ServiceGroup(
        services: observabilityServices + [mindService, healthCheck],
        gracefulShutdownSignals: [.sigterm],
        cancellationSignals: [.sigint],
        logger: Logger(label: "creature-agent")
    )
    try await serviceGroup.run()
}

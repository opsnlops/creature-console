import ArgumentParser
import Common
import Foundation
import Logging
import Observability
import ServiceLifecycle

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
            name: .customLong("trace-open-ai"),
            help: "Log OpenAI response bodies for debugging")
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

            let traceResponses = traceOpenAI || traceOpenAICompat

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

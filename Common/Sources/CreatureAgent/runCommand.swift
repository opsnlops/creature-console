import ArgumentParser
import Common
import Foundation
import Logging

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
            logger.debug("OpenAI model \(config.openAiModel)")
            logger.debug("OpenAI temperature \(config.openAiTemperature)")

            let openAI = OpenAIClient(
                apiKey: config.openAiApiKey,
                model: config.openAiModel,
                systemPrompt: config.openAiSystemPrompt,
                temperature: config.openAiTemperature,
                logger: logger,
                traceResponses: traceOpenAI || traceOpenAICompat
            )

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

            let listener = MQTTAgentListener(
                host: mqttHostValue,
                port: mqttPortValue,
                topics: Array(topicMap.keys),
                reconnectBackoff: config.mqttReconnectBackoff,
                logLevel: loggerLevel
            )

            try await listener.connect { topic, payload, isRetained in
                guard let topicConfig = topicMap[topic] else {
                    logger.warning("Received MQTT message for unknown topic \(topic)")
                    return
                }

                let areaName = topicConfig.area
                let cooldownSeconds = topicConfig.cooldownSeconds
                let prompt = topicConfig.prompt

                let eventTimestamp = MQTTEventTracker.timestamp(from: payload)
                let timestampDescription = eventTimestamp.map { "\($0)" } ?? "nil"
                logger.debug("MQTT timestamp parsed for \(topic): \(timestampDescription)")

                if isRetained {
                    let existingTimestamp = await eventTracker.initialTimestamp(for: topic)
                    if existingTimestamp == nil {
                        await eventTracker.updateInitialTimestamp(
                            for: topic, timestamp: eventTimestamp)
                        logger.debug("Recorded retained MQTT timestamp for \(topic)")
                        return
                    }
                    logger.debug("Processing retained MQTT update for \(topic)")
                }

                let shouldProcess = await eventTracker.shouldProcess(
                    topic: topic,
                    timestamp: eventTimestamp
                )

                guard shouldProcess else {
                    logger.debug("Skipping duplicate/stale MQTT event for \(topic)")
                    return
                }

                logger.info("MQTT event received for topic \(topic)")
                logger.debug("Prompt for topic \(topic): \(prompt)")

                let cooldownWindow = await eventTracker.cooldownWindow(
                    for: areaName,
                    cooldownSeconds: cooldownSeconds
                )
                guard cooldownWindow == nil else {
                    let remaining = String(format: "%.1f", cooldownWindow ?? 0)
                    logger.info(
                        "Skipping MQTT event for area \(areaName) due to cooldown (\(remaining)s remaining)"
                    )
                    return
                }

                do {
                    let response = try await openAI.respond(to: prompt)
                    let sanitized = TextSanitizer.sanitize(response)

                    if sanitized.removedCharacters > 0 {
                        logger.info(
                            "Sanitized OpenAI response for topic \(topic) (removed \(sanitized.removedCharacters) chars)"
                        )
                    }

                    let finalSpeech: String
                    if sanitized.text.isEmpty {
                        finalSpeech = config.fallbackSpeech
                        logger.warning("Using fallback speech for topic \(topic)")
                    } else {
                        finalSpeech = sanitized.text
                    }

                    logger.info("OpenAI response ready for topic \(topic)")

                    let result = await server.createAdHocSpeechAnimation(
                        creatureId: config.creatureId,
                        text: finalSpeech,
                        resumePlaylist: true
                    )

                    switch result {
                    case .success(let job):
                        await eventTracker.markAreaProcessed(areaName)
                        logger.info("Queued ad-hoc speech job \(job.jobId) for topic \(topic)")
                    case .failure(let error):
                        logger.error(
                            "Failed to queue ad-hoc speech for topic \(topic): \(error.localizedDescription)"
                        )
                    }

                } catch {
                    logger.error(
                        "Failed to process MQTT topic \(topic): \(error.localizedDescription)")
                }
            }

            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1))
                }
            } catch {
                // Allow cancellation to break the loop
            }

            logger.info("Shutting down creature-agent")
            await listener.shutdown()
        }
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
    if let serverError = error as? ServerError {
        message = "Failed to find creature \(creatureId) on \(host):\(port): \(serverError)"
    } else {
        message =
            "Failed to find creature \(creatureId) on \(host):\(port): \(error.localizedDescription)"
    }
    fputs("\(message)\n", stderr)
    throw ExitCode.failure
}

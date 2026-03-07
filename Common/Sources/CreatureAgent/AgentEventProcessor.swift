import Common
import Foundation
import Logging
import Metrics
import Tracing

struct AgentEventProcessor: Sendable {
    let topicMap: [String: TopicConfigMap]
    let eventTracker: MQTTEventTracker
    let creatureId: CreatureIdentifier
    let fallbackSpeech: String
    let llmModel: String
    let respondToPrompt: @Sendable (String) async throws -> String
    let createSpeech:
        @Sendable (CreatureIdentifier, String) async -> Result<JobCreatedResponse, ServerError>
    let logger: Logger

    private let eventsReceivedCounter: Counter
    private let eventsProcessedCounter: Counter
    private let eventsSkippedCooldownCounter: Counter
    private let eventsSkippedDuplicateCounter: Counter
    private let openAIRequestsCounter: Counter
    private let openAIErrorsCounter: Counter
    private let speechQueuedCounter: Counter
    private let speechErrorsCounter: Counter

    init(
        topicMap: [String: TopicConfigMap],
        eventTracker: MQTTEventTracker,
        creatureId: CreatureIdentifier,
        fallbackSpeech: String,
        llmModel: String,
        respondToPrompt: @escaping @Sendable (String) async throws -> String,
        createSpeech:
            @escaping @Sendable (CreatureIdentifier, String) async -> Result<
                JobCreatedResponse, ServerError
            >,
        logger: Logger
    ) {
        self.topicMap = topicMap
        self.eventTracker = eventTracker
        self.creatureId = creatureId
        self.fallbackSpeech = fallbackSpeech
        self.llmModel = llmModel
        self.respondToPrompt = respondToPrompt
        self.createSpeech = createSpeech
        self.logger = logger

        self.eventsReceivedCounter = Counter(label: "creature_agent.events.received")
        self.eventsProcessedCounter = Counter(label: "creature_agent.events.processed")
        self.eventsSkippedCooldownCounter = Counter(
            label: "creature_agent.events.skipped",
            dimensions: [("reason", "cooldown")])
        self.eventsSkippedDuplicateCounter = Counter(
            label: "creature_agent.events.skipped",
            dimensions: [("reason", "duplicate")])
        self.openAIRequestsCounter = Counter(label: "creature_agent.openai.requests")
        self.openAIErrorsCounter = Counter(label: "creature_agent.openai.errors")
        self.speechQueuedCounter = Counter(label: "creature_agent.speech.queued")
        self.speechErrorsCounter = Counter(label: "creature_agent.speech.errors")
    }

    func processEvent(topic: String, payload: String, isRetained: Bool) async {
        eventsReceivedCounter.increment()

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
            eventsSkippedDuplicateCounter.increment()
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
            eventsSkippedCooldownCounter.increment()
            let remaining = String(format: "%.1f", cooldownWindow ?? 0)
            logger.info(
                "Skipping MQTT event for area \(areaName) due to cooldown (\(remaining)s remaining)"
            )
            return
        }

        do {
            try await withSpan("agent.process_event") { span in
                span.attributes["mqtt.topic"] = topic
                span.attributes["agent.area"] = areaName

                openAIRequestsCounter.increment()
                let response = try await withSpan("openai.respond") { openAISpan in
                    openAISpan.attributes["openai.model"] = llmModel
                    return try await respondToPrompt(prompt)
                }
                let sanitized = TextSanitizer.sanitize(response)

                if sanitized.removedCharacters > 0 {
                    logger.info(
                        "Sanitized OpenAI response for topic \(topic) (removed \(sanitized.removedCharacters) chars)"
                    )
                }

                let finalSpeech: String
                if sanitized.text.isEmpty {
                    finalSpeech = fallbackSpeech
                    logger.warning("Using fallback speech for topic \(topic)")
                } else {
                    finalSpeech = sanitized.text
                }

                logger.info("OpenAI response ready for topic \(topic)")

                let result = await withSpan("server.create_ad_hoc_speech") { serverSpan in
                    serverSpan.attributes["creature.id"] = creatureId
                    return await createSpeech(creatureId, finalSpeech)
                }

                switch result {
                case .success(let job):
                    eventsProcessedCounter.increment()
                    speechQueuedCounter.increment()
                    await eventTracker.markAreaProcessed(areaName)
                    logger.info(
                        "Queued ad-hoc speech job \(job.jobId) for topic \(topic)")
                case .failure(let error):
                    speechErrorsCounter.increment()
                    span.recordError(error)
                    logger.error(
                        "Failed to queue ad-hoc speech for topic \(topic): \(ServerError.detailedMessage(from: error))"
                    )
                }
            }
        } catch {
            openAIErrorsCounter.increment()
            logger.error(
                "Failed to process MQTT topic \(topic): \(ServerError.detailedMessage(from: error))"
            )
        }
    }
}

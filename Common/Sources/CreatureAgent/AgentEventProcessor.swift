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
    let llmBackend: LLMBackend
    let llmModel: String
    let respondToPrompt: @Sendable (String) async throws -> String
    let respondToPromptStreaming: (@Sendable (String) -> AsyncStream<String>)?
    let createSpeech:
        @Sendable (CreatureIdentifier, String) async -> Result<JobCreatedResponse, ServerError>
    let server: CreatureServerClient?
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
        llmBackend: LLMBackend,
        llmModel: String,
        respondToPrompt: @escaping @Sendable (String) async throws -> String,
        respondToPromptStreaming: (@Sendable (String) -> AsyncStream<String>)? = nil,
        createSpeech:
            @escaping @Sendable (CreatureIdentifier, String) async -> Result<
                JobCreatedResponse, ServerError
            >,
        server: CreatureServerClient? = nil,
        logger: Logger
    ) {
        self.topicMap = topicMap
        self.eventTracker = eventTracker
        self.creatureId = creatureId
        self.fallbackSpeech = fallbackSpeech
        self.llmBackend = llmBackend
        self.llmModel = llmModel
        self.respondToPrompt = respondToPrompt
        self.respondToPromptStreaming = respondToPromptStreaming
        self.createSpeech = createSpeech
        self.server = server
        self.logger = logger

        self.eventsReceivedCounter = Counter(label: "creature_agent.events.received")
        self.eventsProcessedCounter = Counter(label: "creature_agent.events.processed")
        self.eventsSkippedCooldownCounter = Counter(
            label: "creature_agent.events.skipped",
            dimensions: [("reason", "cooldown")])
        self.eventsSkippedDuplicateCounter = Counter(
            label: "creature_agent.events.skipped",
            dimensions: [("reason", "duplicate")])
        self.openAIRequestsCounter = Counter(label: "creature_agent.llm.requests")
        self.openAIErrorsCounter = Counter(label: "creature_agent.llm.errors")
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

        // Mark cooldown immediately so concurrent events for this area are rejected
        // while the LLM + speech pipeline is in flight.
        await eventTracker.markAreaProcessed(areaName)

        do {
            try await withSpan("agent.process_event") { span in
                span.attributes["mqtt.topic"] = topic
                span.attributes["agent.area"] = areaName
                span.attributes["llm.backend"] = llmBackend.rawValue

                openAIRequestsCounter.increment()

                // Use streaming if available — send each sentence to the
                // server as soon as it arrives from the LLM, so the creature
                // starts talking while the LLM is still generating.
                if let streamingRespond = respondToPromptStreaming {
                    span.attributes["llm.streaming"] = true
                    await processEventStreaming(
                        prompt: prompt,
                        topic: topic,
                        span: span,
                        streamingRespond: streamingRespond
                    )
                } else {
                    span.attributes["llm.streaming"] = false
                    let response = try await withSpan("llm.respond") { llmSpan in
                        llmSpan.attributes["llm.backend"] = llmBackend.rawValue
                        llmSpan.attributes["llm.model"] = llmModel
                        return try await respondToPrompt(prompt)
                    }

                    await sendSpeechToServer(
                        text: response, topic: topic, span: span)
                }
            }
        } catch {
            openAIErrorsCounter.increment()
            logger.error(
                "Failed to process MQTT topic \(topic): \(ServerError.detailedMessage(from: error))"
            )
        }
    }

    // MARK: - Streaming LLM pipeline

    /// Process an event using the streaming LLM — opens a streaming session
    /// on the server, sends each sentence as it arrives from the LLM, then
    /// finishes the session to trigger a single uninterrupted playback.
    private func processEventStreaming(
        prompt: String,
        topic: String,
        span: any Span,
        streamingRespond: @Sendable (String) -> AsyncStream<String>
    ) async {
        guard let server = server else {
            logger.warning(
                "No server client for streaming session, falling back to non-streaming")
            do {
                let response = try await respondToPrompt(prompt)
                await sendSpeechToServer(text: response, topic: topic, span: span)
            } catch {
                openAIErrorsCounter.increment()
                logger.error("LLM fallback failed: \(error)")
            }
            return
        }

        // Start a streaming session on the server
        let startResult = await server.startStreamingAdHocSpeech(
            creatureId: creatureId, resumePlaylist: true)

        let sessionId: String
        switch startResult {
        case .success(let response):
            sessionId = response.sessionId
            logger.info(
                "Streaming session started: \(sessionId) for \(topic)")
            span.attributes["streaming.session_id"] = sessionId
        case .failure(let error):
            logger.error(
                "Failed to start streaming session for \(topic): \(ServerError.detailedMessage(from: error)). Falling back to non-streaming."
            )
            // Fall back to collecting all text and sending as one job
            do {
                let response = try await respondToPrompt(prompt)
                await sendSpeechToServer(text: response, topic: topic, span: span)
            } catch {
                openAIErrorsCounter.increment()
                logger.error("LLM fallback failed: \(error)")
            }
            return
        }

        // Stream sentences from LLM to the session
        var sentenceCount = 0
        for await sentence in streamingRespond(prompt) {
            let sanitized = TextSanitizer.sanitize(sentence)
            guard !sanitized.text.isEmpty else { continue }

            sentenceCount += 1
            logger.info(
                "Streaming sentence \(sentenceCount) to session \(sessionId): \"\(sanitized.text)\""
            )

            let textResult = await server.addStreamingAdHocText(
                sessionId: sessionId, text: sanitized.text)
            if case .failure(let error) = textResult {
                logger.error(
                    "Failed to add text to session \(sessionId): \(ServerError.detailedMessage(from: error))"
                )
            }
        }

        if sentenceCount == 0 {
            // LLM returned nothing — add fallback text
            logger.warning(
                "Streaming LLM returned no sentences for \(topic), using fallback")
            _ = await server.addStreamingAdHocText(
                sessionId: sessionId, text: fallbackSpeech)
            sentenceCount = 1
        }

        // Finish the session — this triggers TTS + animation + playback
        logger.info(
            "Finishing streaming session \(sessionId) with \(sentenceCount) sentences")

        let finishResult = await server.finishStreamingAdHocSpeech(
            sessionId: sessionId)

        switch finishResult {
        case .success(let response):
            eventsProcessedCounter.increment()
            speechQueuedCounter.increment()
            span.attributes["speech.sentences"] = sentenceCount
            span.attributes["speech.animation_id"] = response.animationId ?? "unknown"
            logger.info(
                "Streaming session \(sessionId) complete: animation \(response.animationId ?? "unknown")"
            )
        case .failure(let error):
            speechErrorsCounter.increment()
            span.recordError(error)
            logger.error(
                "Streaming session \(sessionId) finish failed: \(ServerError.detailedMessage(from: error))"
            )
        }
    }

    // MARK: - Helpers

    /// Sanitize text and send a single speech request to the server.
    private func sendSpeechToServer(
        text: String,
        topic: String,
        span: any Span
    ) async {
        let sanitized = TextSanitizer.sanitize(text)

        if sanitized.removedCharacters > 0 {
            logger.info(
                "Sanitized LLM response for topic \(topic) (removed \(sanitized.removedCharacters) chars)"
            )
        }

        let finalSpeech: String
        if sanitized.text.isEmpty {
            finalSpeech = fallbackSpeech
            logger.warning("Using fallback speech for topic \(topic)")
        } else {
            finalSpeech = sanitized.text
        }

        logger.info("LLM response ready for topic \(topic)")

        let result = await withSpan("server.create_ad_hoc_speech") { serverSpan in
            serverSpan.attributes["creature.id"] = creatureId
            return await createSpeech(creatureId, finalSpeech)
        }

        switch result {
        case .success(let job):
            eventsProcessedCounter.increment()
            speechQueuedCounter.increment()
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
}

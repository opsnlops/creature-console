import Common
import Foundation
import Logging
import Metrics
import MetricsTestKit
import Testing

@testable import CoreMetrics
@testable import creature_agent
@testable import creature_mqtt

// MARK: - Shared helpers

/// A stub MQTT publisher that records calls and can be configured to throw.
actor StubMQTTPublisher: MQTTPublishing {
    private(set) var publishedMessages: [(value: String, components: [String], retain: Bool)] = []
    var shouldThrow = false

    nonisolated func topicString(for components: [String]) async -> String {
        components.joined(separator: "/")
    }

    func publishString(_ value: String, components: [String], retain: Bool) async throws {
        if shouldThrow {
            throw StubPublishError.forced
        }
        publishedMessages.append((value: value, components: components, retain: retain))
    }

    func setThrows(_ value: Bool) {
        shouldThrow = value
    }

    var publishCount: Int {
        publishedMessages.count
    }
}

enum StubPublishError: Error {
    case forced
}

/// Creates a basic `MQTTMessageProcessor` with the given stub and filter settings.
private func makeMQTTProcessor(
    stub: StubMQTTPublisher,
    hiddenTypes: Set<MQTTMessageProcessor.MessageType> = [],
    allowedTypes: Set<MQTTMessageProcessor.MessageType>? = nil,
    retainMessages: Bool = false
) -> MQTTMessageProcessor {
    MQTTMessageProcessor(
        mqttClient: stub,
        hiddenTypes: hiddenTypes,
        allowedTypes: allowedTypes,
        logLevel: .critical,
        nameResolver: CreatureNameResolver(),
        fetchCreatureName: { _ in nil },
        animationNameResolver: AnimationNameResolver(),
        fetchAnimationName: { _ in nil },
        reloadAnimationNames: { [:] },
        retainMessages: retainMessages
    )
}

/// Builds an `AgentEventProcessor` for testing with configurable closures.
private func makeAgentProcessor(
    topicMap: [String: TopicConfigMap] = [
        "test/topic": TopicConfigMap(area: "lobby", cooldownSeconds: 0, prompt: "Say something")
    ],
    eventTracker: MQTTEventTracker? = nil,
    respondToPrompt: @escaping @Sendable (String) async throws -> String = { _ in
        "Hello from AI"
    },
    createSpeech:
        @escaping @Sendable (CreatureIdentifier, String) async -> Result<
            JobCreatedResponse, ServerError
        > = { _, _ in
            .success(JobCreatedResponse(jobId: "job-1", jobType: .adHocSpeech, message: "ok"))
        }
) -> AgentEventProcessor {
    AgentEventProcessor(
        topicMap: topicMap,
        eventTracker: eventTracker ?? MQTTEventTracker(logger: Logger(label: "test")),
        creatureId: "creature-abc",
        fallbackSpeech: "Fallback speech",
        llmModel: "test-model",
        respondToPrompt: respondToPrompt,
        createSpeech: createSpeech,
        logger: Logger(label: "test")
    )
}

// MARK: - Serialized parent suite

/// All metrics tests share a serialized parent suite to prevent races on the global MetricsSystem.
@Suite("Observability metrics", .serialized)
struct ObservabilityMetricsTests {

    // MARK: - MQTTMessageProcessor metrics

    @Suite("MQTTMessageProcessor metrics")
    struct MQTTMessageProcessorMetricsTests {

        @Test("Hidden type increments filtered counter")
        func hiddenTypeIncrementsFilteredCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let stub = StubMQTTPublisher()
            let processor = makeMQTTProcessor(
                stub: stub,
                hiddenTypes: [.emergencyStop]
            )

            processor.processEmergencyStop(
                EmergencyStop(reason: "test", timestamp: Date()))

            let filtered = try testMetrics.expectCounter(
                "creature_mqtt.messages.filtered")
            #expect(filtered.totalValue == 1)

            let publishCount = await stub.publishCount
            #expect(publishCount == 0)
        }

        @Test("Allowed-types filter increments filtered counter for excluded types")
        func allowedTypesFilterIncrementsFilteredCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let stub = StubMQTTPublisher()
            let processor = makeMQTTProcessor(
                stub: stub,
                allowedTypes: [.notice]
            )

            processor.processEmergencyStop(
                EmergencyStop(reason: "test", timestamp: Date()))

            let filtered = try testMetrics.expectCounter(
                "creature_mqtt.messages.filtered")
            #expect(filtered.totalValue == 1)

            let publishCount = await stub.publishCount
            #expect(publishCount == 0)
        }

        @Test("Publish success increments published counter")
        func publishSuccessIncrementsPublishedCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let stub = StubMQTTPublisher()
            let processor = makeMQTTProcessor(stub: stub)

            var notice = Notice()
            notice.message = "hello"
            processor.processNotice(notice)

            // publishValue fires a detached Task; give it time to complete
            try await Task.sleep(for: .milliseconds(200))

            let published = try testMetrics.expectCounter(
                "creature_mqtt.messages.published")
            #expect(published.totalValue > 0)
        }

        @Test("Publish error increments error counter")
        func publishErrorIncrementsErrorCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let stub = StubMQTTPublisher()
            await stub.setThrows(true)
            let processor = makeMQTTProcessor(stub: stub)

            var notice = Notice()
            notice.message = "hello"
            processor.processNotice(notice)

            // publishValue fires a detached Task; give it time to complete
            try await Task.sleep(for: .milliseconds(200))

            let errors = try testMetrics.expectCounter(
                "creature_mqtt.publish.errors")
            #expect(errors.totalValue > 0)
        }
    }

    // MARK: - AgentEventProcessor metrics

    @Suite("AgentEventProcessor metrics")
    struct AgentEventProcessorMetricsTests {

        @Test("Received counter always increments")
        func receivedCounterAlwaysIncrements() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let processor = makeAgentProcessor()

            let timestamp = "\(Date().timeIntervalSince1970)"
            await processor.processEvent(
                topic: "test/topic", payload: timestamp, isRetained: false)

            let received = try testMetrics.expectCounter(
                "creature_agent.events.received")
            #expect(received.totalValue == 1)
        }

        @Test("Duplicate events increment skipped counter")
        func duplicateEventsIncrementSkippedCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let tracker = MQTTEventTracker(logger: Logger(label: "test"))
            let processor = makeAgentProcessor(eventTracker: tracker)

            let timestamp = "\(Date().timeIntervalSince1970)"

            // First event should be processed
            await processor.processEvent(
                topic: "test/topic", payload: timestamp, isRetained: false)

            // Same timestamp should be skipped as duplicate
            await processor.processEvent(
                topic: "test/topic", payload: timestamp, isRetained: false)

            let received = try testMetrics.expectCounter(
                "creature_agent.events.received")
            #expect(received.totalValue == 2)

            let skipped = try testMetrics.expectCounter(
                "creature_agent.events.skipped",
                [("reason", "duplicate")])
            #expect(skipped.totalValue == 1)
        }

        @Test("Cooldown events increment skipped counter")
        func cooldownEventsIncrementSkippedCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let tracker = MQTTEventTracker(logger: Logger(label: "test"))
            let processor = makeAgentProcessor(
                topicMap: [
                    "test/topic": TopicConfigMap(
                        area: "lobby", cooldownSeconds: 60, prompt: "Say something")
                ],
                eventTracker: tracker
            )

            let now = Date().timeIntervalSince1970
            let ts1 = "\(now)"
            let ts2 = "\(now + 1)"

            // First event processes and marks the area
            await processor.processEvent(
                topic: "test/topic", payload: ts1, isRetained: false)

            // Second event within cooldown window should be skipped
            await processor.processEvent(
                topic: "test/topic", payload: ts2, isRetained: false)

            let skipped = try testMetrics.expectCounter(
                "creature_agent.events.skipped",
                [("reason", "cooldown")])
            #expect(skipped.totalValue == 1)
        }

        @Test("Successful pipeline increments processed and speech queued")
        func successfulPipelineIncrementsCounters() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let processor = makeAgentProcessor()

            let timestamp = "\(Date().timeIntervalSince1970)"
            await processor.processEvent(
                topic: "test/topic", payload: timestamp, isRetained: false)

            let processed = try testMetrics.expectCounter(
                "creature_agent.events.processed")
            #expect(processed.totalValue == 1)

            let speechQueued = try testMetrics.expectCounter(
                "creature_agent.speech.queued")
            #expect(speechQueued.totalValue == 1)
        }

        @Test("OpenAI error increments error counter")
        func openAIErrorIncrementsErrorCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let processor = makeAgentProcessor(
                respondToPrompt: { _ in
                    throw OpenAIClientError.httpError(
                        code: 500, body: "Internal Server Error")
                }
            )

            let timestamp = "\(Date().timeIntervalSince1970)"
            await processor.processEvent(
                topic: "test/topic", payload: timestamp, isRetained: false)

            let openAIErrors = try testMetrics.expectCounter(
                "creature_agent.openai.errors")
            #expect(openAIErrors.totalValue == 1)
        }

        @Test("Speech creation error increments error counter")
        func speechCreationErrorIncrementsErrorCounter() async throws {
            let testMetrics = TestMetrics()
            MetricsSystem.bootstrapInternal(testMetrics)

            let processor = makeAgentProcessor(
                createSpeech: { _, _ in
                    .failure(.serverError("Speech synthesis failed"))
                }
            )

            let timestamp = "\(Date().timeIntervalSince1970)"
            await processor.processEvent(
                topic: "test/topic", payload: timestamp, isRetained: false)

            let speechErrors = try testMetrics.expectCounter(
                "creature_agent.speech.errors")
            #expect(speechErrors.totalValue == 1)
        }
    }
}

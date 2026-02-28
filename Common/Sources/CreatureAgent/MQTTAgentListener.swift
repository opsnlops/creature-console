import Foundation
import Logging
import MQTTNIO
import MQTTSupport
import NIOCore

actor MQTTAgentListener {
    private let mqttHost: String
    private let mqttPort: Int
    private let topics: [String]
    private let logger: Logger
    private let connector: MQTTClientConnector
    private let clientId: String
    private let messageBufferLimit = 100
    private var isConnected = false
    private var listenerRegistered = false
    private var messageContinuation: AsyncStream<MQTTMessage>.Continuation?
    private var messageTask: Task<Void, Never>?
    private var onMessageHandler: (@Sendable (String, String, Bool) async -> Void)?

    private struct MQTTMessage: Sendable {
        let topic: String
        let payload: String
        let isRetained: Bool
        let payloadSize: Int
    }

    init(
        host: String,
        port: Int,
        topics: [String],
        reconnectBackoff: MQTTReconnectBackoff,
        logLevel: Logger.Level
    ) {
        self.mqttHost = host
        self.mqttPort = port
        self.topics = topics

        var logger = Logger(label: "io.opsnlops.creature-agent.mqtt")
        logger.logLevel = logLevel
        self.logger = logger

        let identifier = "creature-agent-\(UUID().uuidString.prefix(8))"
        self.clientId = identifier
        let configuration = MQTTClientConfiguration(
            host: host,
            port: port,
            useTLS: false,
            username: nil,
            password: nil,
            clientId: identifier,
            keepAliveSeconds: 60,
            reconnectBackoff: reconnectBackoff
        )
        self.connector = MQTTClientConnector(
            configuration: configuration,
            logLevel: logLevel,
            label: "io.opsnlops.creature-agent.mqtt"
        )
    }

    func connect(onMessage: @escaping @Sendable (String, String, Bool) async -> Void) async throws {
        if isConnected {
            logger.info("MQTT listener already connected; skipping reconnect")
            return
        }

        onMessageHandler = onMessage
        startMessageProcessingIfNeeded()

        try await connector.connect()
        let subscriptions = topics.map { MQTTSubscribeInfo(topicFilter: $0, qos: .atLeastOnce) }
        try await connector.subscribe(topics: subscriptions)
        isConnected = true

        logger.info("Connected to MQTT broker \(mqttHost):\(mqttPort) as \(clientId)")
        logger.info("Subscribed to MQTT topics: \(topics.joined(separator: ", "))")

        if !listenerRegistered {
            connector.addPublishListener(named: "creature-agent-listener") { [logger] result in
                switch result {
                case .success(let publish):
                    let topic = publish.topicName
                    let payloadSize = publish.payload.readableBytes
                    guard let payload = publish.payload.getString(at: 0, length: payloadSize) else {
                        logger.warning(
                            "MQTT payload decode failed for \(topic) (\(payloadSize) bytes)")
                        return
                    }
                    let isRetained = publish.retain
                    logger.debug("MQTT message received on \(topic) (bytes: \(payloadSize))")
                    Task { @Sendable [topic, payload, isRetained, payloadSize] in
                        await self.enqueueMessage(
                            MQTTMessage(
                                topic: topic,
                                payload: payload,
                                isRetained: isRetained,
                                payloadSize: payloadSize
                            )
                        )
                    }
                case .failure(let error):
                    logger.error("MQTT publish listener error: \(error.localizedDescription)")
                }
            }
            listenerRegistered = true
        }
    }

    func shutdown() async {
        messageContinuation?.finish()
        messageTask?.cancel()
        messageContinuation = nil
        messageTask = nil
        onMessageHandler = nil
        isConnected = false
        await connector.shutdown()
    }

    private func startMessageProcessingIfNeeded() {
        guard messageTask == nil else {
            return
        }

        let stream = AsyncStream<MQTTMessage>(
            bufferingPolicy: .bufferingOldest(messageBufferLimit)
        ) { continuation in
            messageContinuation = continuation
        }

        messageTask = Task { [weak self] in
            guard let self else { return }
            for await message in stream {
                await self.deliverMessage(message)
            }
        }
    }

    private func enqueueMessage(_ message: MQTTMessage) {
        guard let continuation = messageContinuation else {
            logger.warning("Dropping MQTT message for \(message.topic) (listener not ready)")
            return
        }

        switch continuation.yield(message) {
        case .enqueued:
            break
        case .dropped:
            logger.warning(
                "MQTT message buffer full; dropped \(message.topic) payload (\(message.payloadSize) bytes)"
            )
        case .terminated:
            logger.warning("MQTT message buffer terminated; dropped \(message.topic)")
        @unknown default:
            logger.warning("MQTT message buffer returned unexpected state for \(message.topic)")
        }
    }

    private func deliverMessage(_ message: MQTTMessage) async {
        guard let handler = onMessageHandler else {
            logger.warning("Dropping MQTT message for \(message.topic) (handler not set)")
            return
        }

        await handler(message.topic, message.payload, message.isRetained)
    }
}

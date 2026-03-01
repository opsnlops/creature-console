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
    private let maxConcurrentTasks: Int
    private var activeTasks = 0
    private var isConnected = false
    private var listenerRegistered = false
    private var onMessage: (@Sendable (String, String, Bool) async -> Void)?

    init(
        host: String,
        port: Int,
        topics: [String],
        reconnectBackoff: MQTTReconnectBackoff,
        logLevel: Logger.Level,
        maxConcurrentTasks: Int = 3
    ) {
        self.mqttHost = host
        self.mqttPort = port
        self.topics = topics
        self.maxConcurrentTasks = maxConcurrentTasks

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

        self.onMessage = onMessage
        try await connector.connect()
        let subscriptions = topics.map { MQTTSubscribeInfo(topicFilter: $0, qos: .atLeastOnce) }
        try await connector.subscribe(topics: subscriptions)
        isConnected = true

        logger.info("Connected to MQTT broker \(mqttHost):\(mqttPort) as \(clientId)")
        logger.info("Subscribed to MQTT topics: \(topics.joined(separator: ", "))")

        if !listenerRegistered {
            connector.addPublishListener(named: "creature-agent-listener") { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let publish):
                    let topic = publish.topicName
                    let payloadSize = publish.payload.readableBytes
                    guard let payload = publish.payload.getString(at: 0, length: payloadSize) else {
                        Task {
                            await self.logPayloadDecodeFailed(topic: topic, size: payloadSize)
                        }
                        return
                    }
                    let isRetained = publish.retain
                    Task {
                        await self.processIfCapacityAvailable(
                            topic: topic, payload: payload, isRetained: isRetained)
                    }
                case .failure(let error):
                    Task {
                        await self.logPublishError(error)
                    }
                }
            }
            listenerRegistered = true
        }
    }

    private func processIfCapacityAvailable(
        topic: String, payload: String, isRetained: Bool
    ) {
        guard activeTasks < maxConcurrentTasks else {
            logger.warning(
                "Dropping MQTT message on \(topic): at capacity (\(activeTasks)/\(maxConcurrentTasks) active tasks)"
            )
            return
        }
        guard let onMessage else {
            logger.warning("Received MQTT message but no onMessage handler is set")
            return
        }
        activeTasks += 1
        logger.debug(
            "MQTT message received on \(topic) — dispatching task (\(activeTasks)/\(maxConcurrentTasks) active)"
        )
        Task { [weak self] in
            await onMessage(topic, payload, isRetained)
            await self?.taskCompleted()
        }
    }

    private func taskCompleted() {
        activeTasks = max(0, activeTasks - 1)
    }

    private func logPayloadDecodeFailed(topic: String, size: Int) {
        logger.warning("MQTT payload decode failed for \(topic) (\(size) bytes)")
    }

    private func logPublishError(_ error: Error) {
        logger.error(
            "MQTT publish listener error: \(MQTTClientConnector.describeMQTTError(error))")
    }

    func shutdown() async {
        onMessage = nil
        isConnected = false
        await connector.shutdown()
    }
}

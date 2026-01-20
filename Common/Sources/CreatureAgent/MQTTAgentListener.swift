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
        try await connector.connect()
        let subscriptions = topics.map { MQTTSubscribeInfo(topicFilter: $0, qos: .atLeastOnce) }
        try await connector.subscribe(topics: subscriptions)
        logger.info("Subscribed to MQTT topics: \(topics.joined(separator: ", "))")

        connector.addPublishListener(named: "creature-agent-listener") { [logger] result in
            switch result {
            case .success(let publish):
                let topic = publish.topicName
                let payloadSize = publish.payload.readableBytes
                let payload = publish.payload.getString(at: 0, length: payloadSize) ?? ""
                let isRetained = publish.retain
                logger.debug("MQTT message received on \(topic) (bytes: \(payloadSize))")
                Task { @Sendable [topic, payload, isRetained] in
                    await onMessage(topic, payload, isRetained)
                }
            case .failure(let error):
                logger.error("MQTT publish listener error: \(error.localizedDescription)")
            }
        }
    }

    func shutdown() async {
        await connector.shutdown()
    }
}

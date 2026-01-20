import Common
import Foundation
import Logging
import MQTTSupport
import NIOCore

actor MQTTClientManager {
    private let options: MQTTOptions
    private let topicPrefix: String
    private let connector: MQTTClientConnector
    private let allocator = ByteBufferAllocator()

    init(options: MQTTOptions, logLevel: Logger.Level) {
        self.options = options
        let trimmedPrefix = options.topicPrefix.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        self.topicPrefix = trimmedPrefix.isEmpty ? "creatures" : trimmedPrefix

        let identifier = options.clientId ?? "creature-mqtt-\(UUID().uuidString.prefix(8))"
        let configuration = MQTTClientConfiguration(
            host: options.mqttHost,
            port: options.mqttPort,
            useTLS: options.mqttTLS,
            username: options.mqttUsername,
            password: options.mqttPassword,
            clientId: identifier,
            keepAliveSeconds: options.mqttKeepAlive,
            reconnectBackoff: MQTTReconnectBackoff(
                initialDelaySeconds: options.mqttBackoffInitialDelay,
                maxDelaySeconds: options.mqttBackoffMaxDelay,
                maxFailures: options.mqttBackoffMaxFailures
            )
        )
        self.connector = MQTTClientConnector(
            configuration: configuration,
            logLevel: logLevel,
            label: "io.opsnlops.creature-mqtt"
        )
    }

    func connect() async throws {
        try await connector.connect()
    }

    func publishString(
        _ value: String,
        components: [String],
        retain: Bool = false
    ) async throws {
        try await publish(data: Data(value.utf8), components: components, retain: retain)
    }

    func publish(
        data: Data,
        components: [String],
        retain: Bool = false
    ) async throws {
        var buffer = allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        let targetTopic = await connector.topicString(components, prefix: topicPrefix)
        try await connector.publish(
            to: targetTopic, payload: buffer, qos: .atLeastOnce, retain: retain)
    }

    func disconnect() async {
        await connector.disconnect()
    }

    func shutdown() async {
        await connector.shutdown()
    }

    func topicString(for components: [String]) async -> String {
        await connector.topicString(components, prefix: topicPrefix)
    }
}

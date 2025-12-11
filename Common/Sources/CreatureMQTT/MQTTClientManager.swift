import Common
import Foundation
import Logging
import MQTTNIO
import NIOCore
import NIOPosix

actor MQTTClientManager {
    private let options: MQTTOptions
    private let topicPrefix: String
    private let client: MQTTClient
    private let allocator = ByteBufferAllocator()
    private var isConnected = false
    private let logger: Logger

    init(options: MQTTOptions, logLevel: Logger.Level) {
        self.options = options
        let trimmedPrefix = options.topicPrefix.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        self.topicPrefix = trimmedPrefix.isEmpty ? "creatures" : trimmedPrefix

        var logger = Logger(label: "io.opsnlops.creature-mqtt")
        logger.logLevel = logLevel
        self.logger = logger

        let keepAlive = TimeAmount.seconds(Int64(max(options.mqttKeepAlive, 1)))
        let configuration = MQTTClient.Configuration(
            version: .v5_0,
            keepAliveInterval: keepAlive,
            userName: options.mqttUsername,
            password: options.mqttPassword,
            useSSL: options.mqttTLS
        )

        let identifier = options.clientId ?? "creature-mqtt-\(UUID().uuidString.prefix(8))"
        self.client = MQTTClient(
            host: options.mqttHost,
            port: options.mqttPort,
            identifier: identifier,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            logger: logger,
            configuration: configuration
        )

    }

    func connect() async throws {
        guard !isConnected else { return }
        let resumedSession = try await client.connect().get()
        isConnected = true
        logger.info(
            "Connected to MQTT broker \(options.mqttHost):\(options.mqttPort) (resumedSession: \(resumedSession))"
        )
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

        try await publish(buffer: buffer, to: topic(components), retain: retain)
    }

    func disconnect() async {
        guard isConnected else { return }
        do {
            try await client.disconnect().get()
        } catch {
            logger.warning("Failed to cleanly disconnect from MQTT: \(error.localizedDescription)")
        }
        isConnected = false
    }

    func shutdown() async {
        await disconnect()
        await withCheckedContinuation { continuation in
            client.shutdown { error in
                if let error {
                    self.logger.warning(
                        "MQTT client shutdown finished with error: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private func publish(buffer: ByteBuffer, to topic: String, retain: Bool) async throws {
        do {
            try await connectIfNeeded()
            try await client.publish(to: topic, payload: buffer, qos: .atLeastOnce, retain: retain)
                .get()
            logger.debug("Published message to topic \(topic)")
        } catch {
            isConnected = false
            logger.warning(
                "MQTT publish failed for topic \(topic). Attempting reconnect once. Error: \(error.localizedDescription)"
            )
            try await reconnectAndPublish(buffer: buffer, topic: topic, retain: retain)
        }
    }

    func topicString(for components: [String]) -> String {
        topic(components)
    }

    private func connectIfNeeded() async throws {
        if !isConnected {
            try await connect()
        }
    }

    private func reconnectAndPublish(buffer: ByteBuffer, topic: String, retain: Bool) async throws {
        try await connectIfNeeded()
        try await client.publish(to: topic, payload: buffer, qos: .atLeastOnce, retain: retain)
            .get()
        isConnected = true
        logger.debug("Republished message to topic \(topic) after reconnect")
    }

    private func topic(_ components: [String]) -> String {
        let sanitized = components.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !topicPrefix.isEmpty else {
            return sanitized.joined(separator: "/")
        }
        if sanitized.isEmpty {
            return topicPrefix
        }
        return "\(topicPrefix)/\(sanitized.joined(separator: "/"))"
    }
}

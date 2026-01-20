import Foundation
import Logging
import MQTTNIO
import NIOCore
import NIOPosix

public struct MQTTClientConfiguration: Sendable {
    public let host: String
    public let port: Int
    public let useTLS: Bool
    public let username: String?
    public let password: String?
    public let clientId: String
    public let keepAliveSeconds: Int
    public let reconnectBackoff: MQTTReconnectBackoff

    public init(
        host: String,
        port: Int,
        useTLS: Bool,
        username: String?,
        password: String?,
        clientId: String,
        keepAliveSeconds: Int,
        reconnectBackoff: MQTTReconnectBackoff = .default
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.username = username
        self.password = password
        self.clientId = clientId
        self.keepAliveSeconds = keepAliveSeconds
        self.reconnectBackoff = reconnectBackoff
    }
}

public struct MQTTReconnectBackoff: Sendable, Codable {
    public static let `default` = MQTTReconnectBackoff(
        initialDelaySeconds: 2,
        maxDelaySeconds: 30,
        maxFailures: 6
    )

    public let initialDelaySeconds: TimeInterval
    public let maxDelaySeconds: TimeInterval
    public let maxFailures: Int

    public init(initialDelaySeconds: TimeInterval, maxDelaySeconds: TimeInterval, maxFailures: Int)
    {
        self.initialDelaySeconds = max(0.1, initialDelaySeconds)
        self.maxDelaySeconds = max(self.initialDelaySeconds, maxDelaySeconds)
        self.maxFailures = max(1, maxFailures)
    }
}

public actor MQTTClientConnector {
    private let configuration: MQTTClientConfiguration
    private let client: MQTTClient
    private let logger: Logger
    private var isConnected = false
    private var connectTask: Task<Bool, Error>?
    private var consecutiveFailures = 0
    private var nextReconnectAllowedAt: Date?
    private var lastBackoffLogAt: Date?

    public init(configuration: MQTTClientConfiguration, logLevel: Logger.Level, label: String) {
        self.configuration = configuration

        var logger = Logger(label: label)
        logger.logLevel = logLevel
        self.logger = logger

        let keepAlive = TimeAmount.seconds(Int64(max(configuration.keepAliveSeconds, 1)))
        let mqttConfig = MQTTClient.Configuration(
            version: .v5_0,
            keepAliveInterval: keepAlive,
            userName: configuration.username,
            password: configuration.password,
            useSSL: configuration.useTLS
        )

        self.client = MQTTClient(
            host: configuration.host,
            port: configuration.port,
            identifier: configuration.clientId,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            logger: logger,
            configuration: mqttConfig
        )

        self.client.addCloseListener(named: "mqtt-connector-close") { [weak self] result in
            guard let self else { return }
            Task { await self.handleClose(result: result) }
        }
    }

    public func connect() async throws {
        guard !isConnected else { return }
        if let connectTask {
            _ = try await connectTask.value
            return
        }
        let task = Task<Bool, Error> { [client, configuration, logger] in
            logger.debug(
                "Connecting to MQTT \(configuration.host):\(configuration.port) tls=\(configuration.useTLS) version=\(client.configuration.version)"
            )
            return try await client.connect().get()
        }
        connectTask = task
        defer { connectTask = nil }
        let resumedSession = try await task.value
        isConnected = true
        logger.info(
            "Connected to MQTT broker \(configuration.host):\(configuration.port) (resumedSession: \(resumedSession))"
        )
    }

    public func subscribe(topics: [MQTTSubscribeInfo]) async throws {
        if let remaining = backoffRemaining() {
            if shouldLogBackoff(remaining: remaining) {
                logger.warning(
                    "Skipping MQTT subscribe while backing off reconnect (\(String(format: "%.1f", remaining))s remaining)"
                )
            }
            return
        }

        do {
            try await connectIfNeeded()
            _ = try await client.subscribe(to: topics).get()
            resetBackoff()
        } catch {
            isConnected = false
            logger.warning(
                "MQTT subscribe failed. Backing off reconnects for \(String(format: "%.1f", recordFailure()))s. Error: \(describeMQTTError(error))"
            )
            throw error
        }
    }

    public nonisolated func addPublishListener(
        named name: String,
        listener: @escaping @Sendable (Result<MQTTPublishInfo, Error>) -> Void
    ) {
        client.addPublishListener(named: name, listener)
    }

    public func publish(
        to topic: String,
        payload: ByteBuffer,
        qos: MQTTQoS,
        retain: Bool
    ) async throws {
        if let remaining = backoffRemaining() {
            if shouldLogBackoff(remaining: remaining) {
                logger.warning(
                    "Skipping MQTT publish while backing off reconnect (\(String(format: "%.1f", remaining))s remaining)"
                )
            }
            return
        }

        do {
            try await connectIfNeeded()
            try await client.publish(to: topic, payload: payload, qos: qos, retain: retain).get()
            resetBackoff()
            logger.debug("Published message to topic \(topic)")
        } catch {
            isConnected = false
            logger.warning(
                "MQTT publish failed for topic \(topic). Backing off reconnects for \(String(format: "%.1f", recordFailure()))s. Error: \(describeMQTTError(error))"
            )
        }
    }

    public func disconnect() async {
        guard isConnected else { return }
        do {
            try await client.disconnect().get()
        } catch {
            logger.warning("Failed to cleanly disconnect from MQTT: \(error.localizedDescription)")
        }
        isConnected = false
    }

    public func shutdown() async {
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

    public func topicString(_ components: [String], prefix: String) -> String {
        let sanitized = components.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPrefix.isEmpty {
            return sanitized.joined(separator: "/")
        }
        if sanitized.isEmpty {
            return trimmedPrefix
        }
        return "\(trimmedPrefix)/\(sanitized.joined(separator: "/"))"
    }

    private func connectIfNeeded() async throws {
        if isConnected { return }
        try await connect()
    }

    private func handleClose(result: Result<Void, Error>) {
        switch result {
        case .success:
            isConnected = false
            logger.debug("MQTT connection closed by peer")
        case .failure(let error):
            isConnected = false
            logger.warning(
                "MQTT connection closed with error: \(describeMQTTError(error))")
        }
    }

    private func backoffRemaining() -> TimeInterval? {
        guard let deadline = nextReconnectAllowedAt else { return nil }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            nextReconnectAllowedAt = nil
            return nil
        }
        return remaining
    }

    @discardableResult
    private func recordFailure() -> TimeInterval {
        let policy = configuration.reconnectBackoff
        consecutiveFailures = min(consecutiveFailures + 1, policy.maxFailures)
        let delay = min(
            policy.initialDelaySeconds * pow(2.0, Double(consecutiveFailures - 1)),
            policy.maxDelaySeconds
        )
        nextReconnectAllowedAt = Date().addingTimeInterval(delay)
        return delay
    }

    private func resetBackoff() {
        consecutiveFailures = 0
        nextReconnectAllowedAt = nil
        lastBackoffLogAt = nil
    }

    private func shouldLogBackoff(remaining: TimeInterval) -> Bool {
        guard let lastBackoffLogAt else {
            self.lastBackoffLogAt = Date()
            return true
        }
        if Date().timeIntervalSince(lastBackoffLogAt) >= 5 {
            self.lastBackoffLogAt = Date()
            return true
        }
        return false
    }

    private func describeMQTTError(_ error: Error) -> String {
        if let mqttError = error as? MQTTError {
            switch mqttError {
            case .connectionError(let value):
                return "MQTT connectionError: \(value)"
            case .reasonError(let code):
                return "MQTT reasonError: \(code)"
            case .serverDisconnection(let ack):
                return "MQTT serverDisconnection: \(ack)"
            case .serverClosedConnection:
                return "MQTT serverClosedConnection"
            default:
                return "MQTT error: \(mqttError)"
            }
        }
        if let channelError = error as? ChannelError {
            return "ChannelError: \(channelError)"
        }
        return error.localizedDescription
    }
}

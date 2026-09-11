import Foundation

public enum CommunicatorGatewayConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case emptyHost
    case invalidEnvironmentValue(name: String, value: String)
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyHost:
            "Creature Communicator Gateway bind host cannot be empty"
        case .invalidEnvironmentValue(let name, let value):
            "Creature Communicator Gateway environment variable \(name) has an invalid value: \(value)"
        case .invalidPort(let port):
            "Creature Communicator Gateway port must be between 1 and 65535; received \(port)"
        }
    }
}

public struct CommunicatorGatewayConfiguration: Codable, Equatable, Sendable {
    public static let configPathEnvironmentKey = "CREATURE_COMMUNICATOR_GATEWAY_CONFIG"
    public static let hostEnvironmentKey = "SERVER_HOSTNAME"
    public static let portEnvironmentKey = "SERVER_PORT"
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 8_001
    public static let `default` = CommunicatorGatewayConfiguration(
        validatedHost: defaultHost,
        port: defaultPort
    )

    public let host: String
    public let port: Int

    public init(host: String = defaultHost, port: Int = defaultPort) throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw CommunicatorGatewayConfigurationError.emptyHost
        }
        guard (1...65_535).contains(port) else {
            throw CommunicatorGatewayConfigurationError.invalidPort(port)
        }
        self.host = host
        self.port = port
    }

    private init(validatedHost: String, port: Int) {
        host = validatedHost
        self.port = port
    }

    public static func load(
        from url: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CommunicatorGatewayConfiguration {
        let fileConfiguration: CommunicatorGatewayConfiguration
        if let url {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode(RawConfiguration.self, from: data)
            fileConfiguration = try CommunicatorGatewayConfiguration(
                host: raw.host ?? defaultHost,
                port: raw.port ?? defaultPort
            )
        } else {
            fileConfiguration = .default
        }

        let environmentPort = try environment[portEnvironmentKey].map { value in
            guard let port = Int(value) else {
                throw CommunicatorGatewayConfigurationError.invalidEnvironmentValue(
                    name: portEnvironmentKey,
                    value: value
                )
            }
            return port
        }
        return try fileConfiguration.overriding(
            host: environment[hostEnvironmentKey],
            port: environmentPort
        )
    }

    public func overriding(host: String?, port: Int?) throws -> CommunicatorGatewayConfiguration {
        try CommunicatorGatewayConfiguration(
            host: host ?? self.host,
            port: port ?? self.port
        )
    }

    private struct RawConfiguration: Decodable {
        let host: String?
        let port: Int?
    }
}

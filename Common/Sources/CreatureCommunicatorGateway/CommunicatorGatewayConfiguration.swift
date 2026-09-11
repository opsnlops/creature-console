import Foundation

public enum CommunicatorGatewayConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case emptyHost
    case invalidEnvironmentValue(name: String, value: String)
    case invalidPort(Int)
    case invalidWorldURL(String)

    public var errorDescription: String? {
        switch self {
        case .emptyHost:
            "Creature Communicator Gateway bind host cannot be empty"
        case .invalidEnvironmentValue(let name, let value):
            "Creature Communicator Gateway environment variable \(name) has an invalid value: \(value)"
        case .invalidPort(let port):
            "Creature Communicator Gateway port must be between 1 and 65535; received \(port)"
        case .invalidWorldURL(let value):
            "Creature Communicator Gateway World URL is invalid: \(value)"
        }
    }
}

public struct CommunicatorGatewayConfiguration: Codable, Equatable, Sendable {
    public static let configPathEnvironmentKey = "CREATURE_COMMUNICATOR_GATEWAY_CONFIG"
    public static let hostEnvironmentKey = "SERVER_HOSTNAME"
    public static let portEnvironmentKey = "SERVER_PORT"
    public static let worldURLEnvironmentKey = "CREATURE_WORLD_URL"
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 8_002
    public static let defaultWorldURL = URL(string: "http://127.0.0.1:8001/world/v1")!
    public static let `default` = CommunicatorGatewayConfiguration(
        validatedHost: defaultHost,
        port: defaultPort,
        validatedWorldURL: defaultWorldURL
    )

    public let host: String
    public let port: Int
    public let worldURL: URL

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case worldURL = "world_url"
    }

    public init(
        host: String = defaultHost,
        port: Int = defaultPort,
        worldURL: URL = defaultWorldURL
    ) throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw CommunicatorGatewayConfigurationError.emptyHost
        }
        guard (1...65_535).contains(port) else {
            throw CommunicatorGatewayConfigurationError.invalidPort(port)
        }
        guard
            let scheme = worldURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            worldURL.host != nil,
            worldURL.user == nil,
            worldURL.password == nil,
            worldURL.query == nil,
            worldURL.fragment == nil
        else {
            throw CommunicatorGatewayConfigurationError.invalidWorldURL(
                worldURL.absoluteString
            )
        }
        self.host = host
        self.port = port
        self.worldURL = worldURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            host: container.decode(String.self, forKey: .host),
            port: container.decode(Int.self, forKey: .port),
            worldURL: container.decode(URL.self, forKey: .worldURL)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(worldURL, forKey: .worldURL)
    }

    private init(validatedHost: String, port: Int, validatedWorldURL: URL) {
        host = validatedHost
        self.port = port
        worldURL = validatedWorldURL
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
                port: raw.port ?? defaultPort,
                worldURL: try raw.worldURL.map(parseWorldURL) ?? defaultWorldURL
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
            port: environmentPort,
            worldURL: try environment[worldURLEnvironmentKey].map(parseWorldURL)
        )
    }

    public func overriding(
        host: String?,
        port: Int?,
        worldURL: URL? = nil
    ) throws -> CommunicatorGatewayConfiguration {
        try CommunicatorGatewayConfiguration(
            host: host ?? self.host,
            port: port ?? self.port,
            worldURL: worldURL ?? self.worldURL
        )
    }

    private static func parseWorldURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw CommunicatorGatewayConfigurationError.invalidWorldURL(value)
        }
        return url
    }

    private struct RawConfiguration: Decodable {
        let host: String?
        let port: Int?
        let worldURL: String?

        private enum CodingKeys: String, CodingKey {
            case host
            case port
            case worldURL = "world_url"
        }
    }
}

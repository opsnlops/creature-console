import Foundation

enum CreatureWorldConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case emptyHost
    case invalidEnvironmentValue(name: String, value: String)
    case invalidPort(Int)

    var errorDescription: String? {
        switch self {
        case .emptyHost:
            "Creature World bind host cannot be empty"
        case .invalidEnvironmentValue(let name, let value):
            "Creature World environment variable \(name) has an invalid value: \(value)"
        case .invalidPort(let port):
            "Creature World port must be between 1 and 65535; received \(port)"
        }
    }
}

struct CreatureWorldConfiguration: Codable, Equatable, Sendable {
    static let configPathEnvironmentKey = "CREATURE_WORLD_CONFIG"
    static let hostEnvironmentKey = "SERVER_HOSTNAME"
    static let portEnvironmentKey = "SERVER_PORT"
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 8000

    let host: String
    let port: Int

    init(host: String = defaultHost, port: Int = defaultPort) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw CreatureWorldConfigurationError.emptyHost
        }
        guard (1...65_535).contains(port) else {
            throw CreatureWorldConfigurationError.invalidPort(port)
        }
        self.host = trimmedHost
        self.port = port
    }

    static func load(
        from url: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CreatureWorldConfiguration {
        let fileConfiguration: CreatureWorldConfiguration
        if let url {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode(RawConfiguration.self, from: data)
            fileConfiguration = try CreatureWorldConfiguration(
                host: raw.host ?? defaultHost,
                port: raw.port ?? defaultPort
            )
        } else {
            fileConfiguration = try CreatureWorldConfiguration()
        }

        let environmentPort = try environment[portEnvironmentKey].map { value in
            guard let port = Int(value) else {
                throw CreatureWorldConfigurationError.invalidEnvironmentValue(
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

    func overriding(host: String?, port: Int?) throws -> CreatureWorldConfiguration {
        try CreatureWorldConfiguration(host: host ?? self.host, port: port ?? self.port)
    }

    private struct RawConfiguration: Decodable {
        let host: String?
        let port: Int?
    }
}

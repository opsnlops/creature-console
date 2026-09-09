import Foundation
import MongoKitten

enum CreatureWorldConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case emptyAPIToken
    case emptyHost
    case invalidEnvironmentValue(name: String, value: String)
    case invalidMongoURI
    case unexpectedMongoDatabase(expected: String, actual: String?)
    case invalidPort(Int)
    case missingAPIToken(host: String)

    var errorDescription: String? {
        switch self {
        case .emptyAPIToken:
            "Creature World API token cannot be empty"
        case .emptyHost:
            "Creature World bind host cannot be empty"
        case .invalidEnvironmentValue(let name, let value):
            "Creature World environment variable \(name) has an invalid value: \(value)"
        case .invalidMongoURI:
            "Creature World MongoDB URI is invalid"
        case .unexpectedMongoDatabase(let expected, let actual):
            "Creature World MongoDB URI must select the \(expected) database; selected \(actual ?? "none")"
        case .invalidPort(let port):
            "Creature World port must be between 1 and 65535; received \(port)"
        case .missingAPIToken(let host):
            "Creature World requires an API token when binding to \(host)"
        }
    }
}

struct CreatureWorldConfiguration: Codable, Equatable, Sendable {
    static let configPathEnvironmentKey = "CREATURE_WORLD_CONFIG"
    static let apiTokenEnvironmentKey = "CREATURE_WORLD_API_TOKEN"
    static let allowedOriginsEnvironmentKey = "CREATURE_WORLD_ALLOWED_ORIGINS"
    static let hostEnvironmentKey = "SERVER_HOSTNAME"
    static let mongoURIEnvironmentKey = "MONGODB_URI"
    static let portEnvironmentKey = "SERVER_PORT"
    static let defaultHost = "127.0.0.1"
    static let databaseName = "creature_world"
    static let defaultMongoURI =
        "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000"
    static let defaultPort = 8000

    let allowedOrigins: [String]
    let apiToken: String?
    let host: String
    let mongoURI: String
    let port: Int

    init(
        host: String = defaultHost,
        port: Int = defaultPort,
        mongoURI: String = defaultMongoURI,
        apiToken: String? = nil,
        allowedOrigins: [String] = []
    ) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw CreatureWorldConfigurationError.emptyHost
        }
        guard (1...65_535).contains(port) else {
            throw CreatureWorldConfigurationError.invalidPort(port)
        }
        let normalizedToken = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiToken != nil, normalizedToken?.isEmpty != false {
            throw CreatureWorldConfigurationError.emptyAPIToken
        }
        let settings: ConnectionSettings
        do {
            settings = try ConnectionSettings(mongoURI)
        } catch {
            throw CreatureWorldConfigurationError.invalidMongoURI
        }
        guard settings.targetDatabase == Self.databaseName else {
            throw CreatureWorldConfigurationError.unexpectedMongoDatabase(
                expected: Self.databaseName,
                actual: settings.targetDatabase
            )
        }
        self.allowedOrigins =
            allowedOrigins
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.apiToken = normalizedToken
        self.host = trimmedHost
        self.mongoURI = mongoURI
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
                port: raw.port ?? defaultPort,
                mongoURI: raw.mongoURI ?? defaultMongoURI,
                apiToken: raw.apiToken,
                allowedOrigins: raw.allowedOrigins ?? []
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
        let configuredOrigins = environment[allowedOriginsEnvironmentKey].map {
            $0.split(separator: ",").map(String.init)
        }
        let configuration = try fileConfiguration.overriding(
            host: environment[hostEnvironmentKey],
            port: environmentPort,
            mongoURI: environment[mongoURIEnvironmentKey],
            apiToken: environment[apiTokenEnvironmentKey],
            allowedOrigins: configuredOrigins
        )
        try configuration.validateAPIExposure()
        return configuration
    }

    func overriding(
        host: String?,
        port: Int?,
        mongoURI: String? = nil,
        apiToken: String? = nil,
        allowedOrigins: [String]? = nil
    ) throws
        -> CreatureWorldConfiguration
    {
        try CreatureWorldConfiguration(
            host: host ?? self.host,
            port: port ?? self.port,
            mongoURI: mongoURI ?? self.mongoURI,
            apiToken: apiToken ?? self.apiToken,
            allowedOrigins: allowedOrigins ?? self.allowedOrigins
        )
    }

    var requiresAuthentication: Bool {
        !Self.isLoopback(host)
    }

    func validateAPIExposure() throws {
        if requiresAuthentication, apiToken == nil {
            throw CreatureWorldConfigurationError.missingAPIToken(host: host)
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost" || normalized == "::1" || normalized == "[::1]"
            || normalized.hasPrefix("127.")
    }

    private struct RawConfiguration: Decodable {
        let host: String?
        let allowedOrigins: [String]?
        let apiToken: String?
        let mongoURI: String?
        let port: Int?

        private enum CodingKeys: String, CodingKey {
            case host
            case allowedOrigins = "allowed_origins"
            case apiToken = "api_token"
            case mongoURI = "mongodb_uri"
            case port
        }
    }
}

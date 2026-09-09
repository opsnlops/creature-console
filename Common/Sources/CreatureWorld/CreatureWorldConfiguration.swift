import Foundation
import MongoKitten

enum CreatureWorldConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case emptyHost
    case invalidEnvironmentValue(name: String, value: String)
    case invalidMongoURI
    case unexpectedMongoDatabase(expected: String, actual: String?)
    case invalidPort(Int)

    var errorDescription: String? {
        switch self {
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
        }
    }
}

struct CreatureWorldConfiguration: Codable, Equatable, Sendable {
    static let configPathEnvironmentKey = "CREATURE_WORLD_CONFIG"
    static let hostEnvironmentKey = "SERVER_HOSTNAME"
    static let mongoURIEnvironmentKey = "MONGODB_URI"
    static let portEnvironmentKey = "SERVER_PORT"
    static let defaultHost = "127.0.0.1"
    static let databaseName = "creature_world"
    static let defaultMongoURI =
        "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000"
    static let defaultPort = 8000

    let host: String
    let mongoURI: String
    let port: Int

    init(
        host: String = defaultHost,
        port: Int = defaultPort,
        mongoURI: String = defaultMongoURI
    ) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw CreatureWorldConfigurationError.emptyHost
        }
        guard (1...65_535).contains(port) else {
            throw CreatureWorldConfigurationError.invalidPort(port)
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
                mongoURI: raw.mongoURI ?? defaultMongoURI
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
            port: environmentPort,
            mongoURI: environment[mongoURIEnvironmentKey]
        )
    }

    func overriding(host: String?, port: Int?, mongoURI: String? = nil) throws
        -> CreatureWorldConfiguration
    {
        try CreatureWorldConfiguration(
            host: host ?? self.host,
            port: port ?? self.port,
            mongoURI: mongoURI ?? self.mongoURI
        )
    }

    private struct RawConfiguration: Decodable {
        let host: String?
        let mongoURI: String?
        let port: Int?

        private enum CodingKeys: String, CodingKey {
            case host
            case mongoURI = "mongodb_uri"
            case port
        }
    }
}

import Foundation
import MongoKitten
import WorldCore

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
    static let allowedOriginsEnvironmentKey = "CREATURE_WORLD_ALLOWED_ORIGINS"
    static let hostEnvironmentKey = "SERVER_HOSTNAME"
    static let mongoURIEnvironmentKey = "MONGODB_URI"
    static let portEnvironmentKey = "SERVER_PORT"
    static let defaultHost = "127.0.0.1"
    static let databaseName = "creature_world"
    static let defaultMongoURI =
        "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000"
    static let defaultPort = 8001

    let allowedOrigins: [String]
    let host: String
    let mongoURI: String
    let port: Int
    let presence: PresenceConfiguration

    init(
        host: String = defaultHost,
        port: Int = defaultPort,
        mongoURI: String = defaultMongoURI,
        allowedOrigins: [String] = [],
        presence: PresenceConfiguration = PresenceConfiguration()
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
        self.allowedOrigins =
            allowedOrigins
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.host = trimmedHost
        self.mongoURI = mongoURI
        self.port = port
        self.presence = presence
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
                allowedOrigins: raw.allowedOrigins ?? [],
                presence: try PresenceConfiguration(raw: raw.presence)
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
        return try fileConfiguration.overriding(
            host: environment[hostEnvironmentKey],
            port: environmentPort,
            mongoURI: environment[mongoURIEnvironmentKey],
            allowedOrigins: configuredOrigins
        )
    }

    func overriding(
        host: String?,
        port: Int?,
        mongoURI: String? = nil,
        allowedOrigins: [String]? = nil
    ) throws
        -> CreatureWorldConfiguration
    {
        try CreatureWorldConfiguration(
            host: host ?? self.host,
            port: port ?? self.port,
            mongoURI: mongoURI ?? self.mongoURI,
            allowedOrigins: allowedOrigins ?? self.allowedOrigins,
            presence: presence
        )
    }

    private struct RawConfiguration: Decodable {
        let host: String?
        let allowedOrigins: [String]?
        let mongoURI: String?
        let port: Int?
        let presence: RawPresenceConfiguration?

        private enum CodingKeys: String, CodingKey {
            case host
            case allowedOrigins = "allowed_origins"
            case mongoURI = "mongodb_uri"
            case port
            case presence
        }
    }

    struct RawPresenceConfiguration: Decodable {
        let assumed: [String: RawAssumedPresence]?
    }

    struct RawAssumedPresence: Decodable {
        let state: PersonPresenceState
        let physicallyAudible: Bool?
        let confidence: Double?

        private enum CodingKeys: String, CodingKey {
            case state
            case physicallyAudible = "physically_audible"
            case confidence
        }
    }
}

/// Where the world's presence beliefs come from until real evidence (VW-006/VW-013) exists.
///
/// An assumption is an honest, configured default: "April is home and can hear Beaky". Every
/// decision made on it records `basis: assumed`, so the Viewer shows it and evidence can later
/// replace it without anything downstream changing. No assumption means presence is `unknown`.
struct PresenceConfiguration: Codable, Equatable, Sendable {
    struct AssumedPresence: Codable, Equatable, Sendable {
        var state: PersonPresenceState
        var physicallyAudible: Bool
        var confidence: Double

        init(state: PersonPresenceState, physicallyAudible: Bool, confidence: Double) throws {
            guard confidence.isFinite, (0...1).contains(confidence) else {
                throw WorldContractError.invalidConfidence(confidence)
            }
            self.state = state
            self.physicallyAudible = physicallyAudible
            self.confidence = confidence
        }

        private enum CodingKeys: String, CodingKey {
            case state
            case physicallyAudible = "physically_audible"
            case confidence
        }
    }

    var assumed: [EntityID: AssumedPresence]

    init(assumed: [EntityID: AssumedPresence] = [:]) {
        self.assumed = assumed
    }

    init(raw: CreatureWorldConfiguration.RawPresenceConfiguration?) throws {
        var assumed: [EntityID: AssumedPresence] = [:]
        for (rawPersonID, entry) in raw?.assumed ?? [:] {
            assumed[try EntityID(validating: rawPersonID)] = try AssumedPresence(
                state: entry.state,
                physicallyAudible: entry.physicallyAudible ?? false,
                confidence: entry.confidence ?? 1
            )
        }
        self.init(assumed: assumed)
    }
}

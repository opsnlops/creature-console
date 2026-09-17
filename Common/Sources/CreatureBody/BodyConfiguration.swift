import Foundation
import WorldCore

/// How creature-body is configured, the way the world is: a JSON file for the non-secret
/// defaults, environment variables over it, command options over those. The proxy API key,
/// when one is needed, comes only from the environment (CREATURE_PROXY_API_KEY in
/// /etc/default/creature-body); it is never in the file.
struct BodyConfiguration: Equatable, Sendable {
    static let configPathEnvironmentKey = "CREATURE_BODY_CONFIG"
    static let serverHostEnvironmentKey = "CREATURE_SERVER_HOST"
    static let serverPortEnvironmentKey = "CREATURE_SERVER_PORT"
    static let serverTLSEnvironmentKey = "CREATURE_SERVER_TLS"
    static let proxyHostEnvironmentKey = "CREATURE_PROXY_HOST"
    static let proxyAPIKeyEnvironmentKey = "CREATURE_PROXY_API_KEY"
    static let worldURLEnvironmentKey = "CREATURE_WORLD_URL"

    /// Creature Server: on the production host, the server next door, without TLS.
    var serverHost = "127.0.0.1"
    var serverPort = 8000
    var serverUsesTLS = false
    var proxyHost: String?
    var proxyAPIKey: String?
    /// Creature World's API root.
    var worldURL = URL(string: "http://127.0.0.1:8001/world/v1")!
    /// How long a body fact holds without a newer reading: a bird that stops reporting stops
    /// feeling its body, and says so.
    var validForSeconds = 600
    /// A fact is said again only after this many seconds, however much it changes. Two
    /// minutes: the first night a noisy rail said itself every thirty seconds and drowned the
    /// house out of the birds' story.
    var minimumIntervalSeconds = 120
    /// The server's totals climb every tick; they are said this often at most.
    var serverIntervalSeconds = 60
    /// What counts as a change, per reading.
    var thresholds = Thresholds()
    /// Creature name → entity, for the creatures whose names do not slug to their entity
    /// ("Beaky" → character:beaky needs nothing; a creature called "Left Ear" would).
    var characters: [String: EntityID] = [:]

    struct Thresholds: Codable, Equatable, Sendable {
        var temperatureF = 1.0
        var volts = 0.25
        var amps = 0.2
        var watts = 1.0
        var motorAmps = 0.1
        var motorPosition = 10
        /// Dynamixel present-load units, of a range of about ±1000.
        var servoLoad = 50
        var framesPerSecond = 5.0

        init() {}

        /// Any threshold left out of the file keeps its default.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            temperatureF = try container.decodeIfPresent(Double.self, forKey: .temperatureF) ?? 1.0
            volts = try container.decodeIfPresent(Double.self, forKey: .volts) ?? 0.25
            amps = try container.decodeIfPresent(Double.self, forKey: .amps) ?? 0.2
            watts = try container.decodeIfPresent(Double.self, forKey: .watts) ?? 1.0
            motorAmps = try container.decodeIfPresent(Double.self, forKey: .motorAmps) ?? 0.1
            motorPosition = try container.decodeIfPresent(Int.self, forKey: .motorPosition) ?? 10
            servoLoad = try container.decodeIfPresent(Int.self, forKey: .servoLoad) ?? 50
            framesPerSecond =
                try container.decodeIfPresent(Double.self, forKey: .framesPerSecond) ?? 5
        }

        enum CodingKeys: String, CodingKey {
            case temperatureF = "temperature_f"
            case volts, amps, watts
            case motorAmps = "motor_amps"
            case motorPosition = "motor_position"
            case servoLoad = "servo_load"
            case framesPerSecond = "frames_per_second"
        }
    }

    private struct Raw: Codable {
        var serverHost: String?
        var serverPort: Int?
        var serverUsesTLS: Bool?
        var proxyHost: String?
        var worldURL: String?
        var validForSeconds: Int?
        var minimumIntervalSeconds: Int?
        var serverIntervalSeconds: Int?
        var thresholds: Thresholds?
        var characters: [String: String]?

        enum CodingKeys: String, CodingKey {
            case serverHost = "server_host"
            case serverPort = "server_port"
            case serverUsesTLS = "server_uses_tls"
            case proxyHost = "proxy_host"
            case worldURL = "world_url"
            case validForSeconds = "valid_for_seconds"
            case minimumIntervalSeconds = "minimum_interval_seconds"
            case serverIntervalSeconds = "server_interval_seconds"
            case thresholds
            case characters
        }
    }

    static func load(
        from url: URL?, environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> BodyConfiguration {
        var configuration = BodyConfiguration()
        if let url {
            let raw = try JSONDecoder().decode(Raw.self, from: try Data(contentsOf: url))
            if let host = raw.serverHost { configuration.serverHost = host }
            if let port = raw.serverPort { configuration.serverPort = port }
            if let tls = raw.serverUsesTLS { configuration.serverUsesTLS = tls }
            configuration.proxyHost = raw.proxyHost
            if let world = raw.worldURL {
                guard let worldURL = URL(string: world) else {
                    throw BodyConfigurationError.invalidValue(name: "world_url", value: world)
                }
                configuration.worldURL = worldURL
            }
            if let seconds = raw.validForSeconds { configuration.validForSeconds = seconds }
            if let seconds = raw.minimumIntervalSeconds {
                configuration.minimumIntervalSeconds = seconds
            }
            if let seconds = raw.serverIntervalSeconds {
                configuration.serverIntervalSeconds = seconds
            }
            if let thresholds = raw.thresholds { configuration.thresholds = thresholds }
            configuration.characters = try Dictionary(
                uniqueKeysWithValues: (raw.characters ?? [:]).map {
                    ($0.key.lowercased(), try EntityID(validating: $0.value))
                })
        }
        if let host = environment[serverHostEnvironmentKey] { configuration.serverHost = host }
        if let port = environment[serverPortEnvironmentKey] {
            guard let value = Int(port) else {
                throw BodyConfigurationError.invalidValue(
                    name: serverPortEnvironmentKey, value: port)
            }
            configuration.serverPort = value
        }
        if let tls = environment[serverTLSEnvironmentKey] {
            configuration.serverUsesTLS = ["1", "true", "yes"].contains(tls.lowercased())
        }
        if let proxy = environment[proxyHostEnvironmentKey], !proxy.isEmpty {
            configuration.proxyHost = proxy
        }
        if let key = environment[proxyAPIKeyEnvironmentKey], !key.isEmpty {
            configuration.proxyAPIKey = key
        }
        if let world = environment[worldURLEnvironmentKey] {
            guard let worldURL = URL(string: world) else {
                throw BodyConfigurationError.invalidValue(
                    name: worldURLEnvironmentKey, value: world)
            }
            configuration.worldURL = worldURL
        }
        return configuration
    }

    /// The entity a creature's readings belong to: configured, else `character:<name slug>`.
    func character(named name: String) -> EntityID? {
        if let configured = characters[name.lowercased()] { return configured }
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? nil : EntityID(rawValue: "character:\(slug)")
    }
}

enum BodyConfigurationError: Error, LocalizedError {
    case invalidValue(name: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let name, let value): "\(name) has an unusable value: \(value)"
        }
    }
}

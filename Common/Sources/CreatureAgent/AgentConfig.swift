import Common
import Foundation
import MQTTSupport
import Yams

enum LLMBackend: String, Decodable {
    case openai
    case local
}

/// Which reality the agent inhabits: the legacy MQTT topic listener, or Creature World.
enum AgentMode: String, Decodable {
    case mqtt
    case world
}

struct AgentConfig: Decodable {
    let mode: AgentMode
    let creatureId: CreatureIdentifier
    let llmBackend: LLMBackend
    let llmApiKey: String?
    let llmModel: String
    let llmSystemPrompt: String
    let llmTemperature: Double
    /// For OpenAI reasoning models: `low`, `medium`, or `high`. When set, no temperature is
    /// sent (reasoning models refuse one).
    let llmReasoningEffort: String?
    let localLlmHost: String
    let localLlmPort: Int
    let localLlmMaxTokens: Int
    let conversationHistorySize: Int
    let mqttHost: String
    let mqttPort: Int
    let mqttReconnectBackoff: MQTTReconnectBackoff
    let fallbackSpeech: String
    let maxConcurrentTasks: Int
    let minSentenceChars: Int
    let areas: [AreaConfig]
    let world: WorldModeConfig

    /// Settings that only matter when `mode` is `world`.
    struct WorldModeConfig: Equatable {
        static let defaultWorldURL = URL(string: "http://127.0.0.1:8001/world/v1")!
        static let defaultCharacterEntityID = "character:beaky"
        static let defaultPersonEntityID = "person:april"
        static let defaultRegionEntityID = "region:home"
        static let defaultStateDirectory = "/var/lib/creature-agent"
        static let defaultMaximumReplyAge: TimeInterval = 3_600
        static let defaultMaximumContextTurns = 20
        static let defaultLLMTimeout: TimeInterval = 60

        let worldURL: URL
        let characterEntityID: String
        let personEntityID: String
        /// The region this mind logs into; a character is in one region at a time.
        let regionEntityID: String
        let stateDirectory: String
        let maximumReplyAge: TimeInterval
        let maximumContextTurns: Int
        let llmTimeout: TimeInterval
        let stage: StagePolicy
        /// The structured persona file (`docs/personas/<bird>.yaml`); without one the mind
        /// is the plain `llmSystemPrompt`.
        let personaPath: String?
        /// The clock the character lives by. A model cannot do time-zone arithmetic, so it is
        /// told the local wall-clock time in words; the host's zone (often UTC on a server) is
        /// rarely the house's.
        let timeZone: TimeZone

        /// Whether the mind may perform in the room. `physical` asks the world for the stage
        /// before each turn and streams to Creature Server when the answer is the room;
        /// `communicator_only` never asks and lets the world route every turn (2.55 behaviour).
        enum StagePolicy: String, Decodable, Equatable {
            case physical
            case communicatorOnly = "communicator_only"
        }
    }

    struct AreaConfig: Decodable {
        let area: String
        let cooldownTimeSeconds: TimeInterval
        let items: [TopicConfig]

        private enum CodingKeys: String, CodingKey {
            case area
            case cooldownTime
            case cooldownTimeSeconds
            case items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            area = try container.decode(String.self, forKey: .area)
            items = try container.decode([TopicConfig].self, forKey: .items)
            if let seconds = try container.decodeIfPresent(
                Double.self, forKey: .cooldownTimeSeconds)
            {
                cooldownTimeSeconds = seconds
                return
            }
            if let rawValue = try container.decodeIfPresent(String.self, forKey: .cooldownTime) {
                cooldownTimeSeconds = AgentConfig.parseCooldown(rawValue)
                return
            }
            cooldownTimeSeconds = 0
        }
    }

    struct TopicConfig: Decodable {
        let topic: String
        let agentPrompt: String
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case creatureId
        case llmBackend
        case llmApiKey
        case llmModel
        case llmSystemPrompt
        case llmTemperature
        case llmReasoningEffort
        case localLlmHost
        case localLlmPort
        case localLlmMaxTokens
        case conversationHistorySize
        case mqttHost
        case mqttPort
        case mqttReconnectBackoff
        case fallbackSpeech
        case maxConcurrentTasks
        case minSentenceChars
        case areas
        case worldUrl
        case stage
        case regionEntityId
        case timeZone
        case personaPath
        case characterEntityId
        case personEntityId
        case stateDirectory
        case maximumReplyAge
        case maximumContextTurns
        case llmTimeoutSeconds
    }

    private static let cooldownRegex = try? NSRegularExpression(
        pattern: "^(\\d+(?:\\.\\d+)?)([smhd]?)$",
        options: [.caseInsensitive]
    )


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(AgentMode.self, forKey: .mode) ?? .mqtt
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        llmBackend =
            try container.decodeIfPresent(LLMBackend.self, forKey: .llmBackend) ?? .openai
        llmApiKey = try container.decodeIfPresent(String.self, forKey: .llmApiKey)
        llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? "gpt-5.2"
        llmSystemPrompt = try container.decode(String.self, forKey: .llmSystemPrompt)
        llmTemperature =
            try container.decodeIfPresent(Double.self, forKey: .llmTemperature) ?? 1.0
        llmReasoningEffort = try container.decodeIfPresent(
            String.self, forKey: .llmReasoningEffort)
        if let effort = llmReasoningEffort, !["low", "medium", "high"].contains(effort) {
            throw DecodingError.dataCorruptedError(
                forKey: .llmReasoningEffort, in: container,
                debugDescription: "llmReasoningEffort must be low, medium, or high")
        }
        localLlmHost =
            try container.decodeIfPresent(String.self, forKey: .localLlmHost) ?? "10.69.66.4"
        localLlmPort =
            try container.decodeIfPresent(Int.self, forKey: .localLlmPort) ?? 1234
        localLlmMaxTokens =
            try container.decodeIfPresent(Int.self, forKey: .localLlmMaxTokens) ?? 100
        conversationHistorySize =
            try container.decodeIfPresent(Int.self, forKey: .conversationHistorySize) ?? 10
        mqttHost = try container.decodeIfPresent(String.self, forKey: .mqttHost) ?? "10.3.2.5"
        mqttPort = try container.decodeIfPresent(Int.self, forKey: .mqttPort) ?? 1883
        mqttReconnectBackoff =
            try container.decodeIfPresent(
                MQTTReconnectBackoff.self,
                forKey: .mqttReconnectBackoff
            ) ?? .default
        fallbackSpeech =
            try container.decodeIfPresent(String.self, forKey: .fallbackSpeech)
            ?? "Hey April? There's something outside."
        maxConcurrentTasks =
            try container.decodeIfPresent(Int.self, forKey: .maxConcurrentTasks) ?? 3
        minSentenceChars =
            try container.decodeIfPresent(Int.self, forKey: .minSentenceChars) ?? 0
        // The MQTT listener needs topics; the world-resident mind does not.
        areas =
            mode == .mqtt
            ? try container.decode([AreaConfig].self, forKey: .areas)
            : try container.decodeIfPresent([AreaConfig].self, forKey: .areas) ?? []

        let rawWorldURL = try container.decodeIfPresent(String.self, forKey: .worldUrl)
        guard let worldURL = rawWorldURL.map(URL.init(string:)) ?? WorldModeConfig.defaultWorldURL
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .worldUrl,
                in: container,
                debugDescription: "worldUrl must be an absolute URL"
            )
        }
        world = WorldModeConfig(
            worldURL: worldURL,
            characterEntityID: try container.decodeIfPresent(
                String.self, forKey: .characterEntityId)
                ?? WorldModeConfig.defaultCharacterEntityID,
            personEntityID: try container.decodeIfPresent(String.self, forKey: .personEntityId)
                ?? WorldModeConfig.defaultPersonEntityID,
            regionEntityID: try container.decodeIfPresent(String.self, forKey: .regionEntityId)
                ?? WorldModeConfig.defaultRegionEntityID,
            // systemd exports STATE_DIRECTORY for the unit (per instance for creature-agent@),
            // so several minds on one host never share a cursor.
            stateDirectory: try container.decodeIfPresent(String.self, forKey: .stateDirectory)
                ?? ProcessInfo.processInfo.environment["STATE_DIRECTORY"]
                ?? WorldModeConfig.defaultStateDirectory,
            maximumReplyAge: try container.decodeIfPresent(Double.self, forKey: .maximumReplyAge)
                ?? WorldModeConfig.defaultMaximumReplyAge,
            maximumContextTurns: try container.decodeIfPresent(
                Int.self, forKey: .maximumContextTurns)
                ?? WorldModeConfig.defaultMaximumContextTurns,
            llmTimeout: try container.decodeIfPresent(Double.self, forKey: .llmTimeoutSeconds)
                ?? WorldModeConfig.defaultLLMTimeout,
            stage: try container.decodeIfPresent(
                WorldModeConfig.StagePolicy.self, forKey: .stage) ?? .physical,
            personaPath: try container.decodeIfPresent(String.self, forKey: .personaPath),
            timeZone: try container.decodeIfPresent(String.self, forKey: .timeZone).map {
                guard let zone = TimeZone(identifier: $0) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .timeZone, in: container,
                        debugDescription:
                            "timeZone must be an identifier such as America/Los_Angeles"
                    )
                }
                return zone
            } ?? TimeZone.current
        )
    }

    static func load(from url: URL) throws -> AgentConfig {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        return try decoder.decode(AgentConfig.self, from: contents)
    }

    static func parseCooldown(_ value: String) -> TimeInterval {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let regex = cooldownRegex,
            let match = regex.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            ),
            let amountRange = Range(match.range(at: 1), in: trimmed)
        else {
            return 0
        }

        let amount = Double(trimmed[amountRange]) ?? 0
        let unit = match.range(at: 2)
        let unitValue = Range(unit, in: trimmed).map { String(trimmed[$0]) } ?? ""

        switch unitValue.lowercased() {
        case "s", "":
            return amount
        case "m":
            return amount * 60
        case "h":
            return amount * 3600
        case "d":
            return amount * 86400
        default:
            return amount
        }
    }
}

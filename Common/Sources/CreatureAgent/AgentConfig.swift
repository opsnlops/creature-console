import Common
import Foundation
import MQTTSupport
import Yams

enum LLMBackend: String, Decodable {
    case openai
    case local
}

struct AgentConfig: Decodable {
    let creatureId: CreatureIdentifier
    let llmBackend: LLMBackend
    let llmApiKey: String?
    let llmModel: String
    let llmSystemPrompt: String
    let llmTemperature: Double
    let localLlmHost: String
    let localLlmPort: Int
    let localLlmMaxTokens: Int
    let conversationHistorySize: Int
    let mqttHost: String
    let mqttPort: Int
    let mqttReconnectBackoff: MQTTReconnectBackoff
    let fallbackSpeech: String
    let maxConcurrentTasks: Int
    let areas: [AreaConfig]

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
        case creatureId
        case llmBackend
        case llmApiKey
        case llmModel
        case llmSystemPrompt
        case llmTemperature
        case localLlmHost
        case localLlmPort
        case localLlmMaxTokens
        case conversationHistorySize
        case mqttHost
        case mqttPort
        case mqttReconnectBackoff
        case fallbackSpeech
        case maxConcurrentTasks
        case areas
    }

    private static let cooldownRegex = try? NSRegularExpression(
        pattern: "^(\\d+(?:\\.\\d+)?)([smhd]?)$",
        options: [.caseInsensitive]
    )


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        llmBackend =
            try container.decodeIfPresent(LLMBackend.self, forKey: .llmBackend) ?? .openai
        llmApiKey = try container.decodeIfPresent(String.self, forKey: .llmApiKey)
        llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? "gpt-5.2"
        llmSystemPrompt = try container.decode(String.self, forKey: .llmSystemPrompt)
        llmTemperature =
            try container.decodeIfPresent(Double.self, forKey: .llmTemperature) ?? 1.0
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
        areas = try container.decode([AreaConfig].self, forKey: .areas)
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

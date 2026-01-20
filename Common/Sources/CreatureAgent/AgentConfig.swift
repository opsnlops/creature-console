import Common
import Foundation
import MQTTSupport
import Yams

struct AgentConfig: Decodable {
    let creatureId: CreatureIdentifier
    let openAiApiKey: String
    let openAiModel: String
    let openAiSystemPrompt: String
    let openAiTemperature: Double
    let mqttHost: String
    let mqttPort: Int
    let mqttReconnectBackoff: MQTTReconnectBackoff
    let fallbackSpeech: String
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
        case openAiApiKey
        case openAiModel
        case openAiSystemPrompt
        case openAiTemperature
        case mqttHost
        case mqttPort
        case mqttReconnectBackoff
        case fallbackSpeech
        case areas
    }

    private static let cooldownRegex = try? NSRegularExpression(
        pattern: "^(\\d+(?:\\.\\d+)?)([smhd]?)$",
        options: [.caseInsensitive]
    )


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        openAiApiKey = try container.decode(String.self, forKey: .openAiApiKey)
        openAiModel = try container.decodeIfPresent(String.self, forKey: .openAiModel) ?? "gpt-5.2"
        openAiSystemPrompt = try container.decode(String.self, forKey: .openAiSystemPrompt)
        openAiTemperature =
            try container.decodeIfPresent(Double.self, forKey: .openAiTemperature)
            ?? 1.0
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

import Foundation
import Logging

public class VoiceSubscriptionStatus: Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.VoiceSubscriptionStatus")
    public var tier: String
    public var status: String
    public var characterCount: UInt32
    public var characterLimit: UInt32

    public enum CodingKeys: String, CodingKey {
        case tier
        case status
        case characterCount = "character_count"
        case characterLimit = "character_limit"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier = try container.decode(String.self, forKey: .tier)
        status = try container.decode(String.self, forKey: .status)
        characterCount = try container.decode(UInt32.self, forKey: .characterCount)
        characterLimit = try container.decode(UInt32.self, forKey: .characterLimit)
        logger.debug("Created a new VoiceSubscriptionStatus from init(from:)")
    }

    public init(tier: String, status: String, characterCount: UInt32, characterLimit: UInt32) {
        self.tier = tier
        self.status = status
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        logger.debug("Created a new VoiceSubscriptionStatus from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(tier)
        hasher.combine(status)
        hasher.combine(characterCount)
        hasher.combine(characterLimit)
    }

    // The == operator
    public static func == (lhs: VoiceSubscriptionStatus, rhs: VoiceSubscriptionStatus) -> Bool {
        return lhs.tier == rhs.tier && lhs.status == rhs.status
            && lhs.characterCount == rhs.characterCount && lhs.characterLimit == rhs.characterLimit
    }
}

extension VoiceSubscriptionStatus {
    public static func mock() -> VoiceSubscriptionStatus {
        return VoiceSubscriptionStatus(
            tier: "Premium", status: "Active", characterCount: 1000, characterLimit: 5000)
    }
}

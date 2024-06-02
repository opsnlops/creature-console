import Foundation
import Logging

public class Voice: Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Voice")
    public var voiceId: String
    public var name: String

    public enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voiceId = try container.decode(String.self, forKey: .voiceId)
        name = try container.decode(String.self, forKey: .name)
        logger.debug("Created a new Voice from init(from:)")
    }

    public init(voiceId: String, name: String) {
        self.voiceId = voiceId
        self.name = name
        logger.debug("Created a new Voice from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceId)
        hasher.combine(name)
    }

    // The == operator
    public static func == (lhs: Voice, rhs: Voice) -> Bool {
        return lhs.voiceId == rhs.voiceId && lhs.name == rhs.name
    }
}

extension Voice {
    public static func mock() -> Voice {
        return Voice(voiceId: "uniqueVoiceId", name: "Default Voice Name")
    }
}

import Foundation

public struct AdHocSoundEntry: Codable, Equatable, Sendable, Identifiable {

    public let animationId: AnimationIdentifier
    public let createdAt: Date?
    public let soundFilePath: String
    public let sound: Sound

    public var id: String { "\(animationId)-\(sound.fileName)" }

    enum CodingKeys: String, CodingKey {
        case animationId = "animation_id"
        case createdAt = "created_at"
        case soundFilePath = "sound_file"
        case sound
    }

    public init(
        animationId: AnimationIdentifier,
        createdAt: Date?,
        soundFilePath: String,
        sound: Sound
    ) {
        self.animationId = animationId
        self.createdAt = createdAt
        self.soundFilePath = soundFilePath
        self.sound = sound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        animationId = try container.decode(AnimationIdentifier.self, forKey: .animationId)
        soundFilePath = try container.decode(String.self, forKey: .soundFilePath)
        sound = try container.decode(Sound.self, forKey: .sound)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = AdHocSoundEntry.parse(dateString)
        } else {
            createdAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(animationId, forKey: .animationId)
        try container.encode(soundFilePath, forKey: .soundFilePath)
        try container.encode(sound, forKey: .sound)
        if let createdAt {
            let dateString = AdHocSoundEntry.format(createdAt)
            try container.encode(dateString, forKey: .createdAt)
        }
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct AdHocSoundListDTO: Codable, Equatable, Sendable {
    public let count: UInt32
    public let items: [AdHocSoundEntry]

    public init(count: UInt32, items: [AdHocSoundEntry]) {
        self.count = count
        self.items = items
    }
}

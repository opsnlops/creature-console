import Foundation

/// Request payload for generating lip sync data for a sound file.
public struct GenerateLipSyncRequestDTO: Codable {

    public let soundFile: String
    public let allowOverwrite: Bool

    enum CodingKeys: String, CodingKey {
        case soundFile = "sound_file"
        case allowOverwrite = "allow_overwrite"
    }

    public init(soundFile: String, allowOverwrite: Bool = false) {
        self.soundFile = soundFile
        self.allowOverwrite = allowOverwrite
    }
}

import Foundation
import Logging

public class CreatureSpeechResponseDTO: Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.CreatureSpeechResponseDTO")
    public var soundFileName: String
    public var transcriptFileName: String
    public var soundFileSize: UInt32
    public var success: Bool

    public enum CodingKeys: String, CodingKey {
        case soundFileName = "sound_file_name"
        case transcriptFileName = "transcript_file_name"
        case soundFileSize = "sound_file_size"
        case success
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundFileName = try container.decode(String.self, forKey: .soundFileName)
        transcriptFileName = try container.decode(String.self, forKey: .transcriptFileName)
        soundFileSize = try container.decode(UInt32.self, forKey: .soundFileSize)
        success = try container.decode(Bool.self, forKey: .success)
        logger.debug("Created a new CreatureSpeechResponseDTO from init(from:)")
    }

    public init(
        soundFileName: String, transcriptFileName: String, soundFileSize: UInt32, success: Bool
    ) {
        self.soundFileName = soundFileName
        self.transcriptFileName = transcriptFileName
        self.soundFileSize = soundFileSize
        self.success = success
        logger.debug("Created a new CreatureSpeechResponseDTO from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(soundFileName)
        hasher.combine(transcriptFileName)
        hasher.combine(soundFileSize)
        hasher.combine(success)
    }

    // The == operator
    public static func == (lhs: CreatureSpeechResponseDTO, rhs: CreatureSpeechResponseDTO) -> Bool {
        return lhs.soundFileName == rhs.soundFileName
            && lhs.transcriptFileName == rhs.transcriptFileName
            && lhs.soundFileSize == rhs.soundFileSize && lhs.success == rhs.success
    }
}

extension CreatureSpeechResponseDTO {
    public static func mock() -> CreatureSpeechResponseDTO {
        return CreatureSpeechResponseDTO(
            soundFileName: "exampleSound.mp3", transcriptFileName: "exampleTranscript.txt",
            soundFileSize: 500000, success: true)
    }
}

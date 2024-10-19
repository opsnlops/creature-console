import Foundation
import Logging

public class Sound: Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Sound")
    public var fileName: SoundIdentifier
    public var size: UInt32
    public var transcript: String

    // Use the file name for the identifiable thing. Since these are files on the file system, all in the
    // same directory, it's the file name that makes them unique
    public var id: SoundIdentifier {
        return fileName
    }

    public enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case size
        case transcript
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(SoundIdentifier.self, forKey: .fileName)
        size = try container.decode(UInt32.self, forKey: .size)
        transcript = try container.decode(String.self, forKey: .transcript)
        logger.debug("Created a new Sound from init(from:)")
    }

    public init(fileName: SoundIdentifier, size: UInt32, transcript: String) {
        self.fileName = fileName
        self.size = size
        self.transcript = transcript
        logger.debug("Created a new Sound from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(size)
        hasher.combine(transcript)
    }

    // The == operator
    public static func == (lhs: Sound, rhs: Sound) -> Bool {
        return lhs.fileName == rhs.fileName && lhs.size == rhs.size
            && lhs.transcript == rhs.transcript
    }
}

extension Sound {
    public static func mock() -> Sound {
        return Sound(fileName: "amazingSound.mp3", size: 3_409_834, transcript: "")
    }
}

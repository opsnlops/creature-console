import Foundation
import Logging

public final class Sound: Identifiable, Hashable, Equatable, Codable, Sendable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Sound")
    public let fileName: SoundIdentifier
    public let size: UInt32
    public let transcript: String
    public let lipsync: String

    // Use the file name for the identifiable thing. Since these are files on the file system, all in the
    // same directory, it's the file name that makes them unique
    public var id: SoundIdentifier {
        return fileName
    }

    public enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case size
        case transcript
        case lipsync
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(SoundIdentifier.self, forKey: .fileName)
        size = try container.decode(UInt32.self, forKey: .size)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        lipsync = try container.decodeIfPresent(String.self, forKey: .lipsync) ?? ""
        logger.debug("Created a new Sound from init(from:)")
    }

    public init(
        fileName: SoundIdentifier,
        size: UInt32,
        transcript: String = "",
        lipsync: String = ""
    ) {
        self.fileName = fileName
        self.size = size
        self.transcript = transcript
        self.lipsync = lipsync
        logger.debug("Created a new Sound from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(size)
        hasher.combine(transcript)
        hasher.combine(lipsync)
    }

    // The == operator
    public static func == (lhs: Sound, rhs: Sound) -> Bool {
        return lhs.fileName == rhs.fileName && lhs.size == rhs.size
            && lhs.transcript == rhs.transcript && lhs.lipsync == rhs.lipsync
    }
}

extension Sound {
    public static func mock() -> Sound {
        return Sound(fileName: "amazingSound.mp3", size: 3_409_834, transcript: "", lipsync: "")
    }
}

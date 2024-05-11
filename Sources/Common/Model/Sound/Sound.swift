import Foundation
import OSLog

public class Sound : Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "Sound")
    public var fileName: String
    public var size: UInt32

    public enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case size
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        size = try container.decode(UInt32.self, forKey: .size)
        logger.debug("Created a new Sound from init(from:)")
    }

    public init(fileName: String, size: UInt32) {
        self.fileName = fileName
        self.size = size
        logger.debug("Created a new Sound from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(size)
    }

    // The == operator
    public static func ==(lhs: Sound, rhs: Sound) -> Bool {
        return lhs.fileName == rhs.fileName && lhs.size == rhs.size
    }
}

extension Sound {
    public static func mock() -> Sound {
        return Sound(fileName: "amazingSound.mp3", size: 3409834)
    }
}


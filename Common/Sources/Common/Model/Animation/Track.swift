import Foundation
import Logging

/**
 A `Track` is one creature's set of moments in an animation. There could be several tracks in an animation, or just one. It all depends on who is involved.

 The `creatureId` tells the server which Creature this track is connected to. It's up to the server to look up which offset to use for sending frames, not the Console.
 */

public struct Track: Hashable, Equatable, Codable, Identifiable {

    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Track")

    // The `id` property to conform to Identifiable
    public var id: TrackIdentifier
    public var creatureId: CreatureIdentifier
    public var animationId: AnimationIdentifier
    public var frames: [Data]

    public init(
        id: TrackIdentifier, creatureId: CreatureIdentifier, animationId: AnimationIdentifier,
        frames: [Data]
    ) {
        self.id = id
        self.creatureId = creatureId
        self.animationId = animationId
        self.frames = frames
        logger.trace("Created a new Track from init()")
    }

    // Enum for CodingKeys
    public enum CodingKeys: String, CodingKey {
        case id = "id"
        case creatureId = "creature_id"
        case animationId = "animation_id"
        case frames = "frames"
    }

    // Custom Encoder
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)  // Lowercase UUID string
        try container.encode(creatureId.lowercased(), forKey: .creatureId)  // Lowercase UUID string
        try container.encode(animationId.lowercased(), forKey: .animationId)  // Lowercase UUID string
        let base64Frames = frames.map { $0.base64EncodedString() }
        try container.encode(base64Frames, forKey: .frames)
    }

    // Custom Decoder
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(TrackIdentifier.self, forKey: .id)
        self.creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        self.animationId = try container.decode(AnimationIdentifier.self, forKey: .animationId)
        let base64Frames = try container.decode([String].self, forKey: .frames)
        self.frames = try base64Frames.map {
            guard let data = Data(base64Encoded: $0) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .frames,
                    in: container,
                    debugDescription: "Invalid base64 string for frame data.")
            }
            return data
        }
        logger.trace("Created a new Track from decoder")
    }

    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id && lhs.creatureId == rhs.creatureId && lhs.animationId == rhs.animationId
            && lhs.frames.elementsEqual(rhs.frames, by: { $0 == $1 })
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(creatureId)
        hasher.combine(animationId)
        frames.forEach { hasher.combine($0) }  // Hash each frame's data
    }

}

extension Track {
    public static func mock() -> Track {
        // Generate mock IDs and frame data
        let id = TrackIdentifier()
        let creatureId = CreatureIdentifier(UUID().uuidString.lowercased())  // Random UUID as String
        let animationId = AnimationIdentifier(UUID().uuidString.lowercased())  // Random UUID as String
        let frames = (0..<8).map { _ in Data((0..<7).map { _ in UInt8.random(in: 0...255) }) }  // 8 frames of 7 bytes each
        return Track(id: id, creatureId: creatureId, animationId: animationId, frames: frames)
    }
}

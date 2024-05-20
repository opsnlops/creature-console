import Foundation
import Logging

/**
 A `Track` is one creature's set of moments in an animation. There could be several tracks in an animation, or just one. It all depends on who is involved.

 The `creatureId` tells the server which Creature this track is connected to. It's up to the server to look up which offset to use for sending frames, not the Console.
 */


public struct Track: Hashable, Equatable {

    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Track")

    public var id: TrackIdentifier
    var creatureId: CreatureIdentifier
    var animationId: AnimationIdentifier
    var frames: [Data]

    public init(id: TrackIdentifier, creatureId: CreatureIdentifier, animationId: AnimationIdentifier, frames: [Data]) {
        self.id = id
        self.creatureId = creatureId
        self.animationId = animationId
        self.frames = frames
        logger.trace("Created a new Track from init()")
    }

    public enum CodingKeys: String, CodingKey {
        case id = "id"
        case creatureId = "creature_id"
        case animationId = "animation_id"
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
        let creatureId = DataHelper.generateRandomId()
        let animationId = DataHelper.generateRandomId()
        let frames = (0..<5).map { _ in Data((0..<10).map { _ in UInt8.random(in: 0...255) }) }  // 5 frames of 10 bytes each

        return Track(id: id, creatureId: creatureId, animationId: animationId, frames: frames)
    }
}

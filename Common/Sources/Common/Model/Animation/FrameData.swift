import Foundation
import Logging

public struct FrameData: Hashable, Equatable {

    private let logger = Logger(label: "io.opsnlops.CreatureConsole.FrameData")

    public var id: Data
    var creatureId: Data
    var animationId: Data
    var frames: [Data]

    public init(id: Data, creatureId: Data, animationId: Data, frames: [Data]) {
        self.id = id
        self.creatureId = creatureId
        self.animationId = animationId
        self.frames = frames
        logger.trace("Created a new FrameData from init()")
    }

    public static func == (lhs: FrameData, rhs: FrameData) -> Bool {
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


extension FrameData {
    public static func mock() -> FrameData {

        // Generate mock IDs and frame data
        let id = DataHelper.generateRandomData(byteCount: 12)
        let creatureId = DataHelper.generateRandomData(byteCount: 12)
        let animationId = DataHelper.generateRandomData(byteCount: 12)
        let frames = (0..<5).map { _ in Data((0..<10).map { _ in UInt8.random(in: 0...255) }) }  // 5 frames of 10 bytes each

        return FrameData(id: id, creatureId: creatureId, animationId: animationId, frames: frames)
    }
}

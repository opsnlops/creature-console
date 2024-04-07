
import Foundation

/**
 This is an implementation of the "Animation 2.0" spec in our protobufs
 */
struct Animation: Hashable, Equatable {
    
    var id: Data
    var metadata: AnimationMetadata
    var frameData: [FrameData]?
    
    init(id: Data, metadata: AnimationMetadata, frameData: [FrameData]?) {
        self.id = id
        self.metadata = metadata
        self.frameData = frameData
    }
    
    static func ==(lhs: Animation, rhs: Animation) -> Bool {
        lhs.id == rhs.id &&
        lhs.metadata == rhs.metadata &&
        lhs.frameData == rhs.frameData
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(metadata)
        hasher.combine(frameData)
    }
}

extension Animation {
    static func mock() -> Animation {

        let id = DataHelper.generateRandomData(byteCount: 12)
        let metadata = AnimationMetadata.mock()
        let frameData = (0..<5).map { _ in FrameData.mock() }
        
        return Animation(id: id, metadata: metadata, frameData: frameData)
    }
}

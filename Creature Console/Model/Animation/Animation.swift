
import Foundation

/**
 This is an implementation of the "Animation 2.0" spec in our protobufs
 */
class Animation: Hashable, Equatable {
    
    var id: Data
    var metadata: AnimationMetadata
    var frameData: [FrameData]?
    
    init(id: Data, metadata: AnimationMetadata, frameData: [FrameData]?) {
        self.id = id
        self.metadata = metadata
        self.frameData = frameData
    }
    
    convenience init(fromServerAnimation serverAnimation: Server_Animation) {
        let incomingId = serverAnimation.id
        let incomingMetadata = AnimationMetadata(fromServerAnimationMetadata: serverAnimation.metadata)
        let incomingFrameData = serverAnimation.frames.map { FrameData(serverFrameData: $0) }

        self.init(id: incomingId, metadata: incomingMetadata, frameData: incomingFrameData)
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
    
    func toServerAnimation() -> Server_Animation {
        var s = Server_Animation()
        s.metadata = self.metadata.toServerAnimationMetadata()
        
        if let frameData = self.frameData {
            s.frames = frameData.map { $0.toServerFrameData() }
        }
    
        return s
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

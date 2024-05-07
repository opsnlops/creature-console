
import Foundation

/**
 One full animation that has frame data!

 Most of the time we just use the Metadata
 */
class Animation: Hashable, Equatable, Identifiable {

    var id: String
    var metadata: AnimationMetadata
    var frameData: [FrameData]?
    
    init(id: String, metadata: AnimationMetadata, frameData: [FrameData]?) {
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

        let id = DataHelper.generateRandomId()
        let metadata = AnimationMetadata.mock()
        let frameData = (0..<5).map { _ in FrameData.mock() }
        
        return Animation(id: id, metadata: metadata, frameData: frameData)
    }
}

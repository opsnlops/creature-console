
import Foundation

public class PlaylistItem : Hashable, Equatable, Identifiable {

    let animationId : Data
    let weight: Int32

    public init(animationId: Data, weight: Int32) {
        self.animationId = animationId
        self.weight = weight
    }

    public static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        if lhs.animationId == rhs.animationId  && lhs.weight == rhs.weight {
            return true
        }
        
        return false
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animationId)
        hasher.combine(weight)
    }
    
}


extension PlaylistItem {
    public static func mock() -> PlaylistItem {
        let animationId = Data(DataHelper.generateRandomData(byteCount: 12))
        let weight: Int32 = Int32(arc4random_uniform(100)) // Random weight between 0 and 99

        return PlaylistItem(animationId: animationId, weight: weight)
    }
}

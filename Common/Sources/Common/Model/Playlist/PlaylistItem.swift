import Foundation
import Logging

/// **IMPORTANT**: This DTO must stay in sync with `PlaylistItemModel` in the GUI package.
/// Any changes to fields here must be reflected in PlaylistItemModel.swift and vice versa.
public class PlaylistItem: Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.PlaylistItem")
    public var animationId: AnimationIdentifier
    public var weight: UInt32

    // Use the animationId for the identifiable thing.
    public var id: AnimationIdentifier {
        return animationId
    }

    public enum CodingKeys: String, CodingKey {
        case animationId = "animation_id"
        case weight
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        animationId = try container.decode(AnimationIdentifier.self, forKey: .animationId)
        weight = try container.decode(UInt32.self, forKey: .weight)
        logger.debug("Created a new PlaylistItem from init(from:)")
    }

    public init(animationId: AnimationIdentifier, weight: UInt32) {
        self.animationId = animationId
        self.weight = weight
        logger.debug("Created a new PlaylistItem from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(animationId)
        hasher.combine(weight)
    }

    // The == operator
    public static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        return lhs.animationId == rhs.animationId && lhs.weight == rhs.weight
    }
}

extension PlaylistItem {
    public static func mock() -> PlaylistItem {
        let animationId = UUID().uuidString
        let weight: UInt32 = UInt32.random(in: 0..<100)  // Random weight between 0 and 99

        return PlaylistItem(animationId: animationId, weight: weight)
    }
}

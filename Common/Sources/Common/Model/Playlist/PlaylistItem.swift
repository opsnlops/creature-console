import Foundation

/// **IMPORTANT**: This DTO must stay in sync with `PlaylistItemModel` in the GUI package.
/// Any changes to fields here must be reflected in PlaylistItemModel.swift and vice versa.
public struct PlaylistItem: Identifiable, Hashable, Codable, Sendable {
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

    public init(animationId: AnimationIdentifier, weight: UInt32) {
        self.animationId = animationId
        self.weight = weight
    }
}

extension PlaylistItem {
    public static func mock() -> PlaylistItem {
        let animationId = UUID().uuidString
        let weight: UInt32 = UInt32.random(in: 0..<100)  // Random weight between 0 and 99

        return PlaylistItem(animationId: animationId, weight: weight)
    }
}

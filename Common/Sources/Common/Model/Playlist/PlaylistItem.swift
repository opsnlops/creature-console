import Foundation

/// One animation in a playlist, with the weight that decides how often it comes up.
///
/// The server validates both fields: `animation_id` must be a UUID, and `weight` must be in
/// ``PlaylistLimits/itemWeightRange``. Decoding enforces the same rules so a bad value is
/// caught at the wire boundary rather than turning into a 400 on the next save.
///
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        animationId = try container.decode(AnimationIdentifier.self, forKey: .animationId)
        weight = try container.decode(UInt32.self, forKey: .weight)

        guard UUID(uuidString: animationId) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .animationId, in: container,
                debugDescription:
                    "A playlist item's animation_id must be a UUID; got '\(animationId)'."
            )
        }
        guard PlaylistLimits.isValidWeight(weight) else {
            throw DecodingError.dataCorruptedError(
                forKey: .weight, in: container,
                debugDescription:
                    "A playlist item's weight must be \(PlaylistLimits.minimumItemWeight)…\(PlaylistLimits.maximumItemWeight); got \(weight)."
            )
        }
    }

    /// Whether this item is one the server will accept.
    public var isValid: Bool {
        UUID(uuidString: animationId) != nil && PlaylistLimits.isValidWeight(weight)
    }
}

extension PlaylistItem {
    public static func mock() -> PlaylistItem {
        let animationId = UUID().uuidString
        let weight = UInt32.random(in: PlaylistLimits.itemWeightRange)

        return PlaylistItem(animationId: animationId, weight: weight)
    }
}

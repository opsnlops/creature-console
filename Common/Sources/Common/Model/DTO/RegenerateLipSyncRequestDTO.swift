import Foundation

/// Request payload for triggering lip sync generation on an animation.
public struct RegenerateLipSyncRequestDTO: Codable, Sendable {
    public let animationId: String

    enum CodingKeys: String, CodingKey {
        case animationId = "animation_id"
    }

    public init(animationId: String) {
        self.animationId = animationId
    }
}


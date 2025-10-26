import Foundation

/// Request body for POST /api/v1/animation/ad-hoc/play
public struct TriggerAdHocAnimationRequestDTO: Codable, Equatable, Sendable {
    public let animationId: String
    public let resumePlaylist: Bool?

    enum CodingKeys: String, CodingKey {
        case animationId = "animation_id"
        case resumePlaylist = "resume_playlist"
    }

    public init(animationId: String, resumePlaylist: Bool? = nil) {
        self.animationId = animationId
        self.resumePlaylist = resumePlaylist
    }
}

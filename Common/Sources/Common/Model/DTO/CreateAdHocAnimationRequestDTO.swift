import Foundation

/// Request body for POST /api/v1/animation/ad-hoc and /prepare
public struct CreateAdHocAnimationRequestDTO: Codable, Equatable, Sendable {
    public let creatureId: String
    public let text: String
    public let resumePlaylist: Bool?

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case text
        case resumePlaylist = "resume_playlist"
    }

    public init(creatureId: String, text: String, resumePlaylist: Bool? = nil) {
        self.creatureId = creatureId
        self.text = text
        self.resumePlaylist = resumePlaylist
    }
}

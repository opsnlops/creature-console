import Foundation

// MARK: - Streaming Ad-Hoc Speech Session DTOs

public struct StreamingAdHocStartRequest: Encodable {
    public let creatureId: CreatureIdentifier
    public let resumePlaylist: Bool

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case resumePlaylist = "resume_playlist"
    }

    public init(creatureId: CreatureIdentifier, resumePlaylist: Bool) {
        self.creatureId = creatureId
        self.resumePlaylist = resumePlaylist
    }
}

public struct StreamingAdHocStartResponse: Decodable {
    public let sessionId: String
    public let status: String
    public let message: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
        case message
    }
}

public struct StreamingAdHocTextRequest: Encodable {
    public let sessionId: String
    public let text: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case text
    }

    public init(sessionId: String, text: String) {
        self.sessionId = sessionId
        self.text = text
    }
}

public struct StreamingAdHocTextResponse: Decodable {
    public let sessionId: String
    public let status: String
    public let chunksReceived: Int

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
        case chunksReceived = "chunks_received"
    }
}

public struct StreamingAdHocFinishRequest: Encodable {
    public let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct StreamingAdHocFinishResponse: Decodable {
    public let sessionId: String
    public let status: String
    public let message: String
    public let animationId: String?
    public let playbackTriggered: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
        case message
        case animationId = "animation_id"
        case playbackTriggered = "playback_triggered"
    }
}

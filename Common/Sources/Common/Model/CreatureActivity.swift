import Foundation

public struct CreatureActivity: Codable, Sendable {
    public let creatureId: String
    public let state: ActivityState
    public let animationId: String?
    public let sessionId: String?
    public let reason: ActivityReason?
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case state
        case animationId = "animation_id"
        case sessionId = "session_id"
        case reason
        case timestamp
    }
}

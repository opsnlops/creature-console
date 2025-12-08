import Foundation

public struct IdleStateChanged: Codable, Sendable {
    public let creatureId: String
    public let idleEnabled: Bool
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case idleEnabled = "idle_enabled"
        case timestamp
    }
}

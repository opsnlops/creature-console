import Foundation

/// Represents an emergency stop event from a controller node
public struct EmergencyStop: Codable, Sendable {

    public var reason: String
    public var timestamp: Date

    public init() {
        self.reason = ""
        self.timestamp = Date()
    }

    public init(reason: String, timestamp: Date) {
        self.reason = reason
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decode(String.self, forKey: .reason)

        let timestampMs = try container.decode(Int64.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason, forKey: .reason)
        try container.encode(Int64(timestamp.timeIntervalSince1970 * 1000), forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case reason
        case timestamp
    }
}

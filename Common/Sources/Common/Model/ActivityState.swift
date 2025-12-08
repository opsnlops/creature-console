import Foundation

public enum ActivityState: String, Codable, Sendable {
    case running
    case idle
    case disabled
    case stopped
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ActivityState(rawValue: raw) ?? .unknown
    }
}

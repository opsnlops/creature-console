import Foundation

public enum ActivityReason: String, Codable, Sendable {
    case play = "play"
    case playlist = "playlist"
    case adHoc = "ad_hoc"
    case idle = "idle"
    case disabled = "disabled"
    case cancelled = "cancelled"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ActivityReason(rawValue: raw) ?? .unknown
    }
}

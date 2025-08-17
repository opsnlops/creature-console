import Foundation

/// Represents a watchdog warning when a value is approaching its threshold
public struct WatchdogWarning: Codable {

    public var warningType: String
    public var currentValue: Double
    public var threshold: Double
    public var timestamp: Date

    public init() {
        self.warningType = ""
        self.currentValue = 0.0
        self.threshold = 0.0
        self.timestamp = Date()
    }

    public init(warningType: String, currentValue: Double, threshold: Double, timestamp: Date) {
        self.warningType = warningType
        self.currentValue = currentValue
        self.threshold = threshold
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        warningType = try container.decode(String.self, forKey: .warningType)
        currentValue = try container.decode(Double.self, forKey: .currentValue)
        threshold = try container.decode(Double.self, forKey: .threshold)

        let timestampMs = try container.decode(Int64.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(warningType, forKey: .warningType)
        try container.encode(currentValue, forKey: .currentValue)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(Int64(timestamp.timeIntervalSince1970 * 1000), forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case warningType = "warning_type"
        case currentValue = "current_value"
        case threshold
        case timestamp
    }
}

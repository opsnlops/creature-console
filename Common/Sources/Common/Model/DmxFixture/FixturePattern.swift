import Foundation

/// A named DMX value snapshot that bindings (and the manual trigger endpoint) can fire.
public struct FixturePattern: Codable, Hashable, Equatable, Sendable, Identifiable {
    public var id: FixturePatternIdentifier
    public var name: String
    public var values: [FixturePatternValue]
    /// Milliseconds to ramp from the channels' current values to the target. `0` = snap.
    public var fadeInMs: UInt32
    /// Milliseconds to ramp back to pre-pattern values when stopped. `0` = snap.
    public var fadeOutMs: UInt32
    /// Milliseconds to hold the target after fade-in. `0` = hold indefinitely until an
    /// external stop (e.g. the originating binding transitioning out).
    public var holdMs: UInt32

    public init(
        id: FixturePatternIdentifier,
        name: String,
        values: [FixturePatternValue],
        fadeInMs: UInt32 = 0,
        fadeOutMs: UInt32 = 0,
        holdMs: UInt32 = 0
    ) {
        self.id = id
        self.name = name
        self.values = values
        self.fadeInMs = fadeInMs
        self.fadeOutMs = fadeOutMs
        self.holdMs = holdMs
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case values
        case fadeInMs = "fade_in_ms"
        case fadeOutMs = "fade_out_ms"
        case holdMs = "hold_ms"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(FixturePatternIdentifier.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.values = try container.decode([FixturePatternValue].self, forKey: .values)
        self.fadeInMs = try container.decodeIfPresent(UInt32.self, forKey: .fadeInMs) ?? 0
        self.fadeOutMs = try container.decodeIfPresent(UInt32.self, forKey: .fadeOutMs) ?? 0
        self.holdMs = try container.decodeIfPresent(UInt32.self, forKey: .holdMs) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(values, forKey: .values)
        try container.encode(fadeInMs, forKey: .fadeInMs)
        try container.encode(fadeOutMs, forKey: .fadeOutMs)
        try container.encode(holdMs, forKey: .holdMs)
    }
}

import Foundation

/// One channel's target value within a `FixturePattern`. `channel` must match a
/// `FixtureChannel.name` on the parent fixture.
public struct FixturePatternValue: Codable, Hashable, Equatable, Sendable, Identifiable {
    public var channel: String
    public var value: UInt8

    public var id: String { channel }

    public init(channel: String, value: UInt8) {
        self.channel = channel
        self.value = value
    }
}

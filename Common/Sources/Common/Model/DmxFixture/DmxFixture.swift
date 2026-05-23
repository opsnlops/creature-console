import Foundation

/// A first-class DMX device managed by the creature server. Unlike `Creature`, the server's
/// MongoDB is authoritative for fixtures — the Creature Console is the source-of-truth editor.
/// `assignedUniverse` is persisted on the fixture document (survives server restart).
///
/// Modeled as a `struct` (value type) so SwiftUI bindings into nested properties
/// (`$fixture.channels[i].name` etc.) propagate change notifications correctly. A
/// reference type would require `@Observable` or per-edit refresh-ID hacks.
public struct DmxFixture: Identifiable, Hashable, Equatable, Codable, Sendable {

    public var id: DmxFixtureIdentifier
    public var name: String
    public var type: FixtureType
    public var channelOffset: UInt16
    public var assignedUniverse: UInt32?
    public var channels: [FixtureChannel]
    public var patterns: [FixturePattern]
    public var bindings: [FixtureBinding]

    public init(
        id: DmxFixtureIdentifier,
        name: String,
        type: FixtureType,
        channelOffset: UInt16,
        assignedUniverse: UInt32? = nil,
        channels: [FixtureChannel],
        patterns: [FixturePattern] = [],
        bindings: [FixtureBinding] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.channelOffset = channelOffset
        self.assignedUniverse = assignedUniverse
        self.channels = channels
        self.patterns = patterns
        self.bindings = bindings
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case channelOffset = "channel_offset"
        case assignedUniverse = "assigned_universe"
        case channels
        case patterns
        case bindings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(DmxFixtureIdentifier.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decodeIfPresent(FixtureType.self, forKey: .type) ?? .generic
        self.channelOffset = try container.decode(UInt16.self, forKey: .channelOffset)
        self.assignedUniverse = try container.decodeIfPresent(
            UInt32.self, forKey: .assignedUniverse)
        self.channels = try container.decode([FixtureChannel].self, forKey: .channels)
        self.patterns =
            try container.decodeIfPresent([FixturePattern].self, forKey: .patterns) ?? []
        self.bindings =
            try container.decodeIfPresent([FixtureBinding].self, forKey: .bindings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(channelOffset, forKey: .channelOffset)
        try container.encodeIfPresent(assignedUniverse, forKey: .assignedUniverse)
        try container.encode(channels, forKey: .channels)
        try container.encode(patterns, forKey: .patterns)
        try container.encode(bindings, forKey: .bindings)
    }
}

extension DmxFixture {
    public static func mock() -> DmxFixture {
        let patternId = UUID().uuidString.lowercased()
        return DmxFixture(
            id: UUID().uuidString.lowercased(),
            name: "Mock Stage Spot",
            type: .light,
            channelOffset: 500,
            assignedUniverse: 1,
            channels: [
                FixtureChannel(offset: 0, name: "red", kind: FixtureChannelKind.colorRed),
                FixtureChannel(offset: 1, name: "green", kind: FixtureChannelKind.colorGreen),
                FixtureChannel(offset: 2, name: "blue", kind: FixtureChannelKind.colorBlue),
                FixtureChannel(
                    offset: 3, name: "brightness", kind: FixtureChannelKind.masterDimmer),
            ],
            patterns: [
                FixturePattern(
                    id: patternId,
                    name: "Red Glow",
                    values: [
                        FixturePatternValue(channel: "red", value: 255),
                        FixturePatternValue(channel: "brightness", value: 200),
                    ],
                    fadeInMs: 250,
                    fadeOutMs: 500,
                    holdMs: 0)
            ],
            bindings: []
        )
    }
}

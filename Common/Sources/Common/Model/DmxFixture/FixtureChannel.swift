import Foundation

/// One addressable DMX channel within a `DmxFixture`. The channel's absolute DMX address
/// is `DmxFixture.channelOffset + offset`.
public struct FixtureChannel: Codable, Hashable, Equatable, Sendable, Identifiable {
    public var offset: UInt16
    public var name: String
    public var kind: String

    /// `Identifiable` conformance — the channel `name` is unique within a fixture, so it
    /// makes a stable identity for `ForEach` and friends.
    public var id: String { name }

    public init(offset: UInt16, name: String, kind: String = "generic") {
        self.offset = offset
        self.name = name
        self.kind = kind
    }

    public enum CodingKeys: String, CodingKey {
        case offset
        case name
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.offset = try container.decode(UInt16.self, forKey: .offset)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "generic"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(offset, forKey: .offset)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
    }
}

/// Conventional values for `FixtureChannel.kind`. The server treats `kind` as a UI hint
/// only — new values can be added at any time without server changes.
public enum FixtureChannelKind {
    public static let colorRed = "color_red"
    public static let colorGreen = "color_green"
    public static let colorBlue = "color_blue"
    public static let colorWhite = "color_white"
    public static let colorAmber = "color_amber"
    /// Lime (~560 nm, yellow-green) — the "L" in RGBL fixtures. Boosts lumen output and
    /// color rendering in the yellow-green band the RGB emitters cover poorly.
    public static let colorLime = "color_lime"
    public static let colorUV = "color_uv"
    public static let masterDimmer = "master_dimmer"
    public static let strobe = "strobe"
    public static let pan = "pan"
    public static let tilt = "tilt"
    public static let gobo = "gobo"
    public static let generic = "generic"

    public static let all: [String] = [
        colorRed, colorGreen, colorBlue, colorWhite, colorAmber, colorLime, colorUV,
        masterDimmer, strobe, pan, tilt, gobo, generic,
    ]
}

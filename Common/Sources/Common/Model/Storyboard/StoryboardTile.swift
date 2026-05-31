import Foundation

/// One programmable button on a storyboard card.
///
/// Geometry is stored as **fractions of the card** (`0...1`) for position and size, so a card scales
/// proportionally across devices (author on Mac, perform on iPhone). The `id` is part of the document
/// (sent over the wire) so a tile keeps its identity across edits and devices. Storyboards are
/// touch-only — there is no joystick binding.
public struct StoryboardTile: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: UUID
    /// Top-left position as fractions of the card (`0...1`).
    public var x: Double
    public var y: Double
    /// Size as fractions of the card (`0...1`).
    public var width: Double
    public var height: Double
    public var label: String
    public var sfSymbol: String
    public var tintColorHex: String
    public var action: StoryboardAction

    enum CodingKeys: String, CodingKey {
        case id, x, y, width, height, label
        case sfSymbol = "sf_symbol"
        case tintColorHex = "tint_color_hex"
        case action
    }

    public init(
        id: UUID = UUID(),
        x: Double, y: Double, width: Double, height: Double,
        label: String, sfSymbol: String, tintColorHex: String,
        action: StoryboardAction
    ) {
        self.id = id
        self.x = Self.clampPosition(x)
        self.y = Self.clampPosition(y)
        self.width = Self.clampSize(width)
        self.height = Self.clampSize(height)
        self.label = label
        self.sfSymbol = sfSymbol
        self.tintColorHex = tintColorHex
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = UUID(uuidString: rawId) ?? UUID()
        x = Self.clampPosition((try? container.decode(Double.self, forKey: .x)) ?? 0)
        y = Self.clampPosition((try? container.decode(Double.self, forKey: .y)) ?? 0)
        width = Self.clampSize((try? container.decode(Double.self, forKey: .width)) ?? 0.2)
        height = Self.clampSize((try? container.decode(Double.self, forKey: .height)) ?? 0.15)
        label = (try? container.decode(String.self, forKey: .label)) ?? "Button"
        sfSymbol = (try? container.decode(String.self, forKey: .sfSymbol)) ?? "square.fill"
        tintColorHex = (try? container.decode(String.self, forKey: .tintColorHex)) ?? "#0A84FF"
        action =
            (try? container.decode(StoryboardAction.self, forKey: .action))
            ?? .unknown(type: "", raw: [:])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(label, forKey: .label)
        try container.encode(sfSymbol, forKey: .sfSymbol)
        try container.encode(tintColorHex, forKey: .tintColorHex)
        try container.encode(action, forKey: .action)
    }

    /// Clamp a position fraction into `0...1`.
    static func clampPosition(_ value: Double) -> Double { min(max(value, 0), 1) }
    /// Clamp a size fraction into a usable range (min keeps a tile tappable).
    static func clampSize(_ value: Double) -> Double { min(max(value, 0.05), 1) }
}

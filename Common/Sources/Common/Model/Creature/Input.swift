import Foundation
import Logging

/// This is the representation of a `Input`
public class Input: Identifiable, Hashable, Equatable, Codable {
    private var logger = Logger(label: "io.opsnlops.CreatureConsole.Creature.Input")

    public var name: String
    public var slot: UInt16
    public var width: UInt8
    public var joystickAxis: UInt8

    enum CodingKeys: String, CodingKey {
        case name, slot, width
        case joystickAxis = "joystick_axis"
    }

    public init(name: String, slot: UInt16, width: UInt8, joystickAxis: UInt8) {
        self.name = name
        self.slot = slot
        self.width = width
        self.joystickAxis = joystickAxis
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        slot = try container.decode(UInt16.self, forKey: .slot)
        width = try container.decode(UInt8.self, forKey: .width)
        joystickAxis = try container.decode(UInt8.self, forKey: .joystickAxis)

    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(slot, forKey: .slot)
        try container.encode(width, forKey: .width)
        try container.encode(joystickAxis, forKey: .joystickAxis)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(slot)
        hasher.combine(width)
        hasher.combine(joystickAxis)
    }

    public static func == (lhs: Input, rhs: Input) -> Bool {
        lhs.name == rhs.name && lhs.slot == rhs.slot
            && lhs.width == rhs.width
            && lhs.joystickAxis == rhs.joystickAxis
    }

}


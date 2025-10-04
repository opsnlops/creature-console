import Foundation
import Logging

/// This is the representation of a `Input`
///
/// **IMPORTANT**: This DTO must stay in sync with `InputModel` in the GUI package.
/// Any changes to fields here must be reflected in InputModel.swift and vice versa.
public final class Input: Identifiable, Hashable, Equatable, Codable, Sendable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Creature.Input")

    public let name: String
    public let slot: UInt16
    public let width: UInt8
    public let joystickAxis: UInt8

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


extension Input {
    public static func mock() -> Input {
        let names = ["head_tilt", "neck_rotate", "beak", "stand_lean", "Clutch"]
        let randomName = names.randomElement() ?? "Control"
        let randomSlot = UInt16.random(in: 0...511)
        let randomWidth: UInt8 = UInt8.random(in: 1...2)
        let randomJoystickAxis = UInt8.random(in: 0...7)

        return Input(
            name: randomName, slot: randomSlot, width: randomWidth, joystickAxis: randomJoystickAxis
        )
    }
}

import Foundation

public class BoardPowerSensors: ObservableObject, Codable, Hashable, Identifiable {

    public let id = UUID() // Unique identifier for each instance
    @Published public var name: String
    @Published public var current: Double
    @Published public var power: Double
    @Published public var voltage: Double

    enum CodingKeys: String, CodingKey {
        case name, current, power, voltage
    }

    public init(name: String, current: Double, power: Double, voltage: Double) {
        self.name = name
        self.current = current
        self.power = power
        self.voltage = voltage
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        current = try container.decode(Double.self, forKey: .current)
        power = try container.decode(Double.self, forKey: .power)
        voltage = try container.decode(Double.self, forKey: .voltage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(current, forKey: .current)
        try container.encode(power, forKey: .power)
        try container.encode(voltage, forKey: .voltage)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(current)
        hasher.combine(power)
        hasher.combine(voltage)
    }

    public static func == (lhs: BoardPowerSensors, rhs: BoardPowerSensors) -> Bool {
        lhs.name == rhs.name && lhs.current == rhs.current
            && lhs.power == rhs.power && lhs.voltage == rhs.voltage
    }
}

extension BoardPowerSensors {
    public static func mock() -> BoardPowerSensors {
        return BoardPowerSensors(
            name: "VBUS",
            current: 0.435,
            power: 42.69,
            voltage: 4.95
        )
    }
}

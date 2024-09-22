import Foundation

/// The sensors that we have on a motor
public class MotorSensors: ObservableObject, Codable, Hashable {

    @Published public var motorNumber: Int
    @Published public var position: Int
    @Published public var current: Double
    @Published public var power: Double
    @Published public var voltage: Double

    enum CodingKeys: String, CodingKey {
        case motorNumber = "number"
        case position, current, power, voltage
    }

    public init(motorNumber: Int, position: Int, current: Double, power: Double, voltage: Double) {
        self.motorNumber = motorNumber
        self.position = position
        self.current = current
        self.power = power
        self.voltage = voltage
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        motorNumber = try container.decode(Int.self, forKey: .motorNumber)
        position = try container.decode(Int.self, forKey: .position)
        current = try container.decode(Double.self, forKey: .current)
        power = try container.decode(Double.self, forKey: .power)
        voltage = try container.decode(Double.self, forKey: .voltage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(motorNumber, forKey: .motorNumber)
        try container.encode(position, forKey: .position)
        try container.encode(current, forKey: .current)
        try container.encode(power, forKey: .power)
        try container.encode(voltage, forKey: .voltage)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(motorNumber)
        hasher.combine(position)
        hasher.combine(current)
        hasher.combine(power)
        hasher.combine(voltage)
    }

    public static func == (lhs: MotorSensors, rhs: MotorSensors) -> Bool {
        lhs.motorNumber == rhs.motorNumber && lhs.position == rhs.position
            && lhs.current == rhs.current && lhs.power == rhs.power && lhs.voltage == rhs.voltage
    }
}

extension MotorSensors {
    public static func mock() -> MotorSensors {
        return MotorSensors(
            motorNumber: 1,
            position: 100,
            current: 10.5,
            power: 25.0,
            voltage: 12.0
        )
    }
}


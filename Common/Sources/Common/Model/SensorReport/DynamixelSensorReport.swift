import Foundation

/// A report of the Dynamixel servo telemetry for a creature
///
/// The server forwards one of these (as a `dynamixel-sensor-report` message)
/// for every creature that has Dynamixel motors on its bus, alongside the
/// regular `motor-sensor-report` used for standard servos.
public final class DynamixelSensorReport: Codable, Hashable, Sendable {

    public let creatureId: CreatureIdentifier
    public let creatureName: String?
    public let motors: [DynamixelSensors]
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case creatureName
        case motors = "dynamixel_motors"
        case timestamp
    }

    public init(
        creatureId: CreatureIdentifier, creatureName: String? = nil,
        motors: [DynamixelSensors], timestamp: Date = .now
    ) {
        self.creatureId = creatureId
        self.creatureName = creatureName
        self.motors = motors
        self.timestamp = timestamp
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        creatureName = try container.decodeIfPresent(String.self, forKey: .creatureName)
        motors = try container.decode([DynamixelSensors].self, forKey: .motors)
        timestamp = .now
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encodeIfPresent(creatureName, forKey: .creatureName)
        try container.encode(motors, forKey: .motors)
        try container.encode(timestamp, forKey: .timestamp)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(creatureName)
        hasher.combine(motors)
        hasher.combine(timestamp)
    }

    public static func == (lhs: DynamixelSensorReport, rhs: DynamixelSensorReport) -> Bool {
        lhs.creatureId == rhs.creatureId && lhs.creatureName == rhs.creatureName
            && lhs.motors == rhs.motors && lhs.timestamp == rhs.timestamp
    }
}

extension DynamixelSensorReport {
    public static func mock() -> DynamixelSensorReport {
        return DynamixelSensorReport(
            creatureId: "MockCreatureID",
            creatureName: "Mock Creature",
            motors: [DynamixelSensors.mock()]
        )
    }
}

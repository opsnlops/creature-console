import Foundation

public final class MotorSensorReport: Codable, Hashable, Sendable {

    public let creatureId: CreatureIdentifier
    public let motors: [MotorSensors]
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case motors
        case timestamp
    }

    public init(
        creatureId: CreatureIdentifier, motors: [MotorSensors], timestamp: Date = .now
    ) {
        self.creatureId = creatureId
        self.motors = motors
        self.timestamp = timestamp
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        motors = try container.decode([MotorSensors].self, forKey: .motors)
        timestamp = .now
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(motors, forKey: .motors)
        try container.encode(timestamp, forKey: .timestamp)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(motors)
        hasher.combine(timestamp)
    }

    public static func == (lhs: MotorSensorReport, rhs: MotorSensorReport) -> Bool {
        lhs.creatureId == rhs.creatureId
            && lhs.motors == rhs.motors && lhs.timestamp == rhs.timestamp
    }
}

extension MotorSensorReport {
    public static func mock() -> MotorSensorReport {
        return MotorSensorReport(
            creatureId: "MockCreatureID",
            motors: [MotorSensors.mock()]
        )
    }
}

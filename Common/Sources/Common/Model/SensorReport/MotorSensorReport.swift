import Foundation

public class MotorSensorReport: ObservableObject, Codable, Hashable {

    @Published public var creatureId: CreatureIdentifier
    @Published public var motors: [MotorSensors]

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case motors
    }

    public init(
        creatureId: CreatureIdentifier, motors: [MotorSensors]
    ) {
        self.creatureId = creatureId
        self.motors = motors
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        motors = try container.decode([MotorSensors].self, forKey: .motors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(motors, forKey: .motors)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(motors)
    }

    public static func == (lhs: MotorSensorReport, rhs: MotorSensorReport) -> Bool {
        lhs.creatureId == rhs.creatureId
            && lhs.motors == rhs.motors
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


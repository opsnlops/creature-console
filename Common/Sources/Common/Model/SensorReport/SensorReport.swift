import Foundation

public class SensorReport: ObservableObject, Codable, Hashable {

    @Published public var creatureId: CreatureIdentifier
    @Published public var boardTemperature: Double
    @Published public var motors: [MotorSensorReport]

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case boardTemperature = "board_temperature"
        case motors
    }

    public init(
        creatureId: CreatureIdentifier, boardTemperature: Double, motors: [MotorSensorReport]
    ) {
        self.creatureId = creatureId
        self.boardTemperature = boardTemperature
        self.motors = motors
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        boardTemperature = try container.decode(Double.self, forKey: .boardTemperature)
        motors = try container.decode([MotorSensorReport].self, forKey: .motors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(boardTemperature, forKey: .boardTemperature)
        try container.encode(motors, forKey: .motors)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(boardTemperature)
        hasher.combine(motors)
    }

    public static func == (lhs: SensorReport, rhs: SensorReport) -> Bool {
        lhs.creatureId == rhs.creatureId && lhs.boardTemperature == rhs.boardTemperature
            && lhs.motors == rhs.motors
    }
}

extension SensorReport {
    public static func mock() -> SensorReport {
        return SensorReport(
            creatureId: "MockCreatureID",
            boardTemperature: 25.0,
            motors: [MotorSensorReport.mock()]
        )
    }
}

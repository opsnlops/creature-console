import Foundation

public class BoardSensorReport: ObservableObject, Codable, Hashable {

    @Published public var creatureId: CreatureIdentifier
    @Published public var boardTemperature: Double
    @Published public var powerReports: [BoardPowerSensors]

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case boardTemperature = "board_temperature"
        case powerReports = "power_reports"
    }

    public init(
        creatureId: CreatureIdentifier, boardTemperature: Double, powerReports: [BoardPowerSensors]
    ) {
        self.creatureId = creatureId
        self.boardTemperature = boardTemperature
        self.powerReports = powerReports
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        boardTemperature = try container.decode(Double.self, forKey: .boardTemperature)
        powerReports = try container.decode([BoardPowerSensors].self, forKey: .powerReports)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(boardTemperature, forKey: .boardTemperature)
        try container.encode(powerReports, forKey: .powerReports)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(creatureId)
        hasher.combine(boardTemperature)
        hasher.combine(powerReports)
    }

    public static func == (lhs: BoardSensorReport, rhs: BoardSensorReport) -> Bool {
        lhs.creatureId == rhs.creatureId && lhs.boardTemperature == rhs.boardTemperature
            && lhs.powerReports == rhs.powerReports
    }
}

extension BoardSensorReport {
    public static func mock() -> BoardSensorReport {
        return BoardSensorReport(
            creatureId: "MockCreatureID",
            boardTemperature: 25.0,
            powerReports: [BoardPowerSensors.mock()]
        )
    }
}

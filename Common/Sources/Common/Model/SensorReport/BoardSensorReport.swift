import Foundation

public class BoardSensorReport: Codable, Hashable, Identifiable {

    public let id = UUID()
    public var creatureId: CreatureIdentifier
    public var boardTemperature: Double
    public var powerReports: [BoardPowerSensors]
    public var timestamp: Date = .now

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case boardTemperature = "board_temperature"
        case powerReports = "power_reports"
        case timestamp
    }

    public init(
        creatureId: CreatureIdentifier, boardTemperature: Double, timestamp: Date = .now,
        powerReports: [BoardPowerSensors]
    ) {
        self.creatureId = creatureId
        self.boardTemperature = boardTemperature
        self.timestamp = timestamp
        self.powerReports = powerReports
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatureId = try container.decode(CreatureIdentifier.self, forKey: .creatureId)
        boardTemperature = try container.decode(Double.self, forKey: .boardTemperature)

        // We're not sending a timestamp
        //timestamp = try container.decode(Date.self, forKey: .timestamp)
        powerReports = try container.decode([BoardPowerSensors].self, forKey: .powerReports)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creatureId, forKey: .creatureId)
        try container.encode(boardTemperature, forKey: .boardTemperature)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(powerReports, forKey: .powerReports)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(creatureId)
        hasher.combine(boardTemperature)
        hasher.combine(timestamp)
        hasher.combine(powerReports)
    }

    public static func == (lhs: BoardSensorReport, rhs: BoardSensorReport) -> Bool {
        lhs.id == rhs.id && lhs.creatureId == rhs.creatureId
            && lhs.boardTemperature == rhs.boardTemperature
            && lhs.timestamp == rhs.timestamp && lhs.powerReports == rhs.powerReports
    }
}

extension BoardSensorReport {
    public static func mock() -> BoardSensorReport {
        return BoardSensorReport(
            creatureId: "MockCreatureID",
            boardTemperature: 25.0,
            timestamp: .now,
            powerReports: [BoardPowerSensors.mock()]
        )
    }
}

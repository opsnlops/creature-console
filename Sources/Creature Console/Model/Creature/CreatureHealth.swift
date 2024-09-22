import Common
import Foundation
import Logging

/// This combines all of the sensors a creature has into one object that can be cached
public class CreatureHealth: ObservableObject, Identifiable, Hashable, Equatable {
    private var logger = Logger(label: "io.opsnlops.CreatureConsole.CreatureHealth")

    public let id: CreatureIdentifier
    public var boardTemperature: Double
    public var boardPowerSensors: [BoardPowerSensors]
    public var motorSensors: [MotorSensors]

    public init(
        id: CreatureIdentifier, boardTemperature: Double, boardPowerSensors: [BoardPowerSensors],
        motorSensors: [MotorSensors]
    ) {
        self.id = id
        self.boardTemperature = boardTemperature
        self.boardPowerSensors = boardPowerSensors
        self.motorSensors = motorSensors
        logger.debug("CreatureHealth for \(id) initialized")
    }

    public func updateBoardTemperature(_ newTemperature: Double) {
        logger.debug("Updating board temperature from \(boardTemperature) to \(newTemperature)")
        self.boardTemperature = newTemperature
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(boardTemperature)
        hasher.combine(boardPowerSensors)
        hasher.combine(motorSensors)
    }

    public static func == (lhs: CreatureHealth, rhs: CreatureHealth) -> Bool {
        lhs.id == rhs.id && lhs.boardTemperature == rhs.boardTemperature
            && lhs.boardPowerSensors == rhs.boardPowerSensors
            && lhs.motorSensors == rhs.motorSensors
    }
}

extension CreatureHealth {
    public static func mock() -> CreatureHealth {
        return CreatureHealth(
            id: "creature_123",
            boardTemperature: 42.0,
            boardPowerSensors: [BoardPowerSensors.mock()],
            motorSensors: [MotorSensors.mock()]
        )
    }
}

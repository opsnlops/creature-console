import Testing
import Foundation
import Common
@testable import Creature_Console

@Suite("CreatureHealth basics")
struct CreatureHealthTests {

    @Test("initializes with provided values")
    func initializesWithValues() throws {
        let id = "creature_123"
        let temperature = 42.0
        let powerSensors = [BoardPowerSensors(name: "VBUS", current: 0.5, power: 2.5, voltage: 5.0)]
        let motorSensors = [MotorSensors(motorNumber: 1, position: 100, current: 1.2, power: 3.4, voltage: 12.0)]

        let health = CreatureHealth(id: id, boardTemperature: temperature, boardPowerSensors: powerSensors, motorSensors: motorSensors)

        #expect(health.id == id)
        #expect(health.boardTemperature == temperature)
        #expect(health.boardPowerSensors == powerSensors)
        #expect(health.motorSensors == motorSensors)
    }

    @Test("updates board temperature")
    func updatesBoardTemperature() throws {
        let health = CreatureHealth.mock()
        let newTemp = health.boardTemperature + 5.5
        health.updateBoardTemperature(newTemp)
        #expect(health.boardTemperature == newTemp)
    }

    @Test("equatable and hashable semantics")
    func equatableAndHashable() throws {
        let a = CreatureHealth(
            id: "same",
            boardTemperature: 10,
            boardPowerSensors: [BoardPowerSensors(name: "A", current: 0.1, power: 1.0, voltage: 3.3)],
            motorSensors: [MotorSensors(motorNumber: 1, position: 1, current: 0.1, power: 1.0, voltage: 12.0)]
        )
        let b = CreatureHealth(
            id: "same",
            boardTemperature: 10,
            boardPowerSensors: [BoardPowerSensors(name: "A", current: 0.1, power: 1.0, voltage: 3.3)],
            motorSensors: [MotorSensors(motorNumber: 1, position: 1, current: 0.1, power: 1.0, voltage: 12.0)]
        )
        let c = CreatureHealth(
            id: "different",
            boardTemperature: 12,
            boardPowerSensors: [BoardPowerSensors(name: "B", current: 0.2, power: 2.0, voltage: 5.0)],
            motorSensors: [MotorSensors(motorNumber: 2, position: 2, current: 0.2, power: 2.0, voltage: 24.0)]
        )

        #expect(a == b)
        #expect(a != c)

        var set = Set([a])
        #expect(set.contains(b))
        _ = set.insert(c)
        #expect(set.count == 2)
    }
}

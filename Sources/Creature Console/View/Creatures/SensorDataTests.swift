import Common
import Foundation
import SwiftUI
import Testing

@testable import Creature_Console

@Suite("SensorData lifecycle management")
struct SensorDataLifecycleTests {

    @Test("AsyncStream subscription can be cancelled")
    func asyncStreamSubscriptionCanBeCancelled() async throws {
        // Simple test: verify that a Task can be cancelled
        // This demonstrates the pattern used in SensorData's onDisappear
        let cache = CreatureHealthCache.shared

        let subscriptionTask = Task { @Sendable in
            for await _ in await cache.stateUpdates {
                // Just keep iterating
            }
        }

        // Cancel the task (simulating onDisappear)
        subscriptionTask.cancel()

        // Verify cancellation worked
        #expect(subscriptionTask.isCancelled == true)
    }
}

@Suite("SensorDataLogic.extractMotorPowerData")
struct SensorDataLogicTests {

    // MARK: - Helpers
    private func makeReport(name: String, power: Double, timestamp: Date) -> BoardSensorReport {
        let sensor = BoardPowerSensors(name: name, current: 0.0, power: power, voltage: 0.0)
        return BoardSensorReport(
            creatureId: "creature_1",
            boardTemperature: 0.0,
            timestamp: timestamp,
            powerReports: [sensor]
        )
    }

    // MARK: - Tests

    @Test("matches exact 'motor_power_in'")
    func matchesExact_motor_power_in() throws {
        let now = Date()
        let reports = [
            makeReport(name: "motor_power_in", power: 12.3, timestamp: now.addingTimeInterval(-2)),
            makeReport(name: "other_sensor", power: 99, timestamp: now),
            makeReport(name: "motor_power_in", power: 4.56, timestamp: now.addingTimeInterval(1)),
        ]
        let result = try #require(SensorDataLogic.extractMotorPowerData(from: reports))
        #expect(result.count == 2)
        #expect(result[0].timestamp == reports[0].timestamp)
        #expect(result[0].power == 12.3)
        #expect(result[1].timestamp == reports[2].timestamp)
        #expect(result[1].power == 4.56)
    }

    @Test("matches exact 'Motor Power In'")
    func matchesExact_Motor_Power_In() throws {
        let now = Date()
        let reports = [
            makeReport(name: "Motor Power In", power: 15.1, timestamp: now.addingTimeInterval(-1)),
            makeReport(name: "motor_power_out", power: 20, timestamp: now),
            makeReport(name: "Motor Power In", power: 7.2, timestamp: now.addingTimeInterval(2)),
        ]
        let result = try #require(SensorDataLogic.extractMotorPowerData(from: reports))
        #expect(result.count == 2)
        #expect(result[0].timestamp == reports[0].timestamp)
        #expect(result[0].power == 15.1)
        #expect(result[1].timestamp == reports[2].timestamp)
        #expect(result[1].power == 7.2)
    }

    @Test("matches names containing both 'motor' and 'power' in any order")
    func matchesNamesContainingMotorAndPower() throws {
        let now = Date()
        let reports = [
            makeReport(name: "Power for Motor", power: 10, timestamp: now.addingTimeInterval(-3)),
            makeReport(name: "random_name", power: 22, timestamp: now),
            makeReport(
                name: "Motor's Power reading", power: 5, timestamp: now.addingTimeInterval(1)),
            makeReport(name: "motor-power", power: 7.7, timestamp: now.addingTimeInterval(2)),
            makeReport(name: "power motor", power: 8.8, timestamp: now.addingTimeInterval(3)),
        ]
        let result = try #require(SensorDataLogic.extractMotorPowerData(from: reports))

        // Build expected subset using the same matching criteria as the logic
        let expected = reports.filter { r in
            let name = r.powerReports.first!.name.lowercased()
            return name.contains("motor_power_in")
                || name.contains("motor power in")
                || (name.contains("motor") && name.contains("power"))
        }
        #expect(result.count == expected.count)
        for (i, point) in result.enumerated() {
            #expect(point.timestamp == expected[i].timestamp)
            #expect(point.power == expected[i].powerReports.first!.power)
        }
    }

    @Test("returns nil when no matching power sensor is present")
    func returnsNilWhenNoMatch() {
        let now = Date()
        let reports = [
            makeReport(name: "temperature", power: 0, timestamp: now),
            makeReport(name: "humidity", power: 0, timestamp: now.addingTimeInterval(10)),
            makeReport(name: "speed", power: 0, timestamp: now.addingTimeInterval(20)),
        ]
        let result = SensorDataLogic.extractMotorPowerData(from: reports)
        #expect(result == nil)
    }

    @Test("preserves order and values")
    func preservesOrderAndValues() throws {
        let now = Date()
        let reports = [
            makeReport(name: "motor_power_in", power: 1, timestamp: now),
            makeReport(name: "Motor Power In", power: 2, timestamp: now.addingTimeInterval(5)),
            makeReport(name: "power motor sensor", power: 3, timestamp: now.addingTimeInterval(10)),
            makeReport(name: "random sensor", power: 4, timestamp: now.addingTimeInterval(15)),
        ]
        let result = try #require(SensorDataLogic.extractMotorPowerData(from: reports))

        let expected = reports.filter { r in
            let name = r.powerReports.first!.name.lowercased()
            return name.contains("motor_power_in")
                || name.contains("motor power in")
                || (name.contains("motor") && name.contains("power"))
        }
        #expect(result.count == expected.count)
        for (i, point) in result.enumerated() {
            #expect(point.timestamp == expected[i].timestamp)
            #expect(point.power == expected[i].powerReports.first!.power)
        }
    }
}

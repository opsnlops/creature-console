import Foundation
import Common

// A top-level data model for motor power points, decoupled from the View layer.
struct SensorPowerDataPoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let power: Double
}

enum SensorDataLogic {
    /// Extracts points for "Motor Power In" from a series of board sensor reports.
    /// Matching is intentionally flexible to accommodate various incoming names.
    static func extractMotorPowerData(from reports: [BoardSensorReport]) -> [SensorPowerDataPoint]? {
        var motorPowerData: [SensorPowerDataPoint] = []

        for report in reports {
            // Prefer explicit IN names first
            if let motorPowerSensor = report.powerReports.first(where: { sensor in
                let name = sensor.name.lowercased()
                return name.contains("motor_power_in") || name.contains("motor power in")
            }) {
                motorPowerData.append(
                    SensorPowerDataPoint(
                        timestamp: report.timestamp,
                        power: motorPowerSensor.power
                    )
                )
                continue
            }

            // Otherwise, allow generic matches that include both words but explicitly exclude OUT
            if let motorPowerSensor = report.powerReports.first(where: { sensor in
                let name = sensor.name.lowercased()
                return name.contains("motor") && name.contains("power") && !name.contains("out")
            }) {
                motorPowerData.append(
                    SensorPowerDataPoint(
                        timestamp: report.timestamp,
                        power: motorPowerSensor.power
                    )
                )
            }
        }

        return motorPowerData.isEmpty ? nil : motorPowerData
    }
}


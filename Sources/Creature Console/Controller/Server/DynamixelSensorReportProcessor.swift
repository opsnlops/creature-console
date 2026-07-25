import Common
import Foundation

struct DynamixelSensorReportMessageProcessor {

    public static func processDynamixelSensorReport(
        _ dynamixelSensorReport: DynamixelSensorReport
    ) async {
        await CreatureHealthCache.shared.addDynamixelSensorData(
            dynamixelSensorReport, forCreature: dynamixelSensorReport.creatureId)
    }
}

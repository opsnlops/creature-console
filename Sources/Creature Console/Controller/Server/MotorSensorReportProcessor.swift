import Common
import Foundation

struct MotorSensorReportMessageProcessor {

    public static func processMotorSensorReport(_ motorSenseReport: MotorSensorReport) async {
        await CreatureHealthCache.shared.addMotorSensorData(
            motorSenseReport, forCreature: motorSenseReport.creatureId)
    }
}

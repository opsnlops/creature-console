import Common
import Foundation
import OSLog
import SwiftUI

struct MotorSensorReportMessageProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MotorSensorReportMessageProcessor")

    public static func processMotorSensorReport(_ motorSenseReport: MotorSensorReport) async {

        logger.debug("Received motor sensor report for creature: \(motorSenseReport.creatureId)")

        await CreatureHealthCache.shared.addMotorSensorData(
            motorSenseReport, forCreature: motorSenseReport.creatureId)
    }
}

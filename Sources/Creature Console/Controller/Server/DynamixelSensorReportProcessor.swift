import Common
import Foundation
import OSLog
import SwiftUI

struct DynamixelSensorReportMessageProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DynamixelSensorReportMessageProcessor")

    public static func processDynamixelSensorReport(
        _ dynamixelSensorReport: DynamixelSensorReport
    ) async {

        logger.debug(
            "Received Dynamixel sensor report for creature: \(dynamixelSensorReport.creatureId)")

        await CreatureHealthCache.shared.addDynamixelSensorData(
            dynamixelSensorReport, forCreature: dynamixelSensorReport.creatureId)
    }
}

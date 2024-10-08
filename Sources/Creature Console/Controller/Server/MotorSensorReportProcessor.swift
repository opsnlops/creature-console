import Common
import Foundation
import OSLog
import SwiftUI

struct MotorSensorReportMessageProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MotorSensorReportMessageProcessor")

    public static func processMotorSensorReport(_ motorSenseReport: MotorSensorReport) {

        logger.debug("Received motor sensor report for creature: \(motorSenseReport.creatureId)")

        let cache = CreatureHealthCache.shared
        cache.addMotorSensorData(motorSenseReport, forCreature: motorSenseReport.creatureId)
    }
}


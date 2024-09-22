import Common
import Foundation
import OSLog

struct BoardSensorReportMessageProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "BoardSensorReportMessageProcessor")

    public static func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {

        logger.debug("Received board sensor report for creature: \(boardSensorReport.creatureId)")

        let cache = CreatureHealthCache.shared
        cache.updateCreature(boardSensorReport)
    }

}

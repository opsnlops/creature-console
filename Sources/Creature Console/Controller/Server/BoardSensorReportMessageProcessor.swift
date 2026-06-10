import Common
import Foundation
import OSLog

struct BoardSensorReportMessageProcessor {

    static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "BoardSensorReportMessageProcessor")

    public static func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) async {

        logger.debug("Received board sensor report for creature: \(boardSensorReport.creatureId)")

        await CreatureHealthCache.shared.addBoardSensorData(
            boardSensorReport, forCreature: boardSensorReport.creatureId)
    }

}

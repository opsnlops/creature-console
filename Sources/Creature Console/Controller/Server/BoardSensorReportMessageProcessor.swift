import Common
import Foundation

struct BoardSensorReportMessageProcessor {

    public static func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) async {
        await CreatureHealthCache.shared.addBoardSensorData(
            boardSensorReport, forCreature: boardSensorReport.creatureId)
    }
}

import Common
import Foundation

struct SensorReportMessageProcessor {

    public static func processSensorReport(_ sensorReport: SensorReport) {
        print("Sensor report: temperature: \(sensorReport.boardTemperature)F")
    }
}


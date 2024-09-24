import Charts
import Common
import Foundation
import OSLog
import SwiftUI

struct SensorData: View {

    var creature: Creature

    let gradient = Gradient(colors: [.green, .yellow, .orange, .red])


    @ObservedObject private var healthCache = CreatureHealthCache.shared

    let numberFormatter = Decimal.FormatStyle.number

    var body: some View {


        let healthReport = healthCache.allBoardSensorData(forCreature: creature.id)
        switch healthReport {
        case .success(let report):
            VStack {

                if let latestReport = report.last {

                    // If we have a temperature, show it
                    Text("Temperature: \(String(format: "%.1f", latestReport.boardTemperature))°F")

                    // Extract the temperature points from the report
                    let temperaturePoints = report.map { TemperaturePoint(timestamp: $0.timestamp, temperature: $0.boardTemperature) }

                    // Swift Charts Line Plot for temperature over time
                    Chart(temperaturePoints) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Temperature", point.temperature)
                        )
                    }
                    .frame(height: 200)


                    HStack {
                        if !latestReport.powerReports.isEmpty {
                            ForEach(latestReport.powerReports.indices, id: \.self) { index in
                                let sensor = latestReport.powerReports[index]
                                VoltageMeterView(title: sensor.name, minValue: 0.0, maxValue: 5.0, currentValue: sensor.voltage)


                            }
                        }
                    }
                    .frame(height: 400)
                }


            }
        case .failure:
                Text("\(creature.name) has not sent a health report yet")
        }

    }



    // Model to represent temperature data at a point in time
    struct TemperaturePoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let temperature: Double
    }

}

#Preview {
    SensorData(creature: Creature.mock())
}

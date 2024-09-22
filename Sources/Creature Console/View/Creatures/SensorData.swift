import Charts
import Common
import Foundation
import OSLog
import SwiftUI

struct SensorData: View {

    var creature: Creature

    let gradient = Gradient(colors: [.green, .yellow, .orange, .red])
    @State private var temperatureHistory: [TemperaturePoint] = []


    @ObservedObject private var healthCache = CreatureHealthCache.shared

    let numberFormatter = Decimal.FormatStyle.number

    var body: some View {


        let healthReport = healthCache.getById(id: creature.id)
        switch healthReport {
        case .success(let report):
            VStack {

                // If we have a temperature, show it
                if !report.boardTemperature.isNaN {

                    Text("Temperature: \(report.boardTemperature)°F")
                    .onAppear {
                        // Add the current temperature to the history when the view appears
                        addTemperatureToHistory(report.boardTemperature)
                    }
                    .onChange(of: report.boardTemperature) { oldTemperature, newTemperature in
                        // Add the updated temperature to the history when it changes
                        if oldTemperature != newTemperature {
                            addTemperatureToHistory(newTemperature)
                        }
                    }

                    Text("Board Temperature: \(report.boardTemperature)")

                    // Swift Charts Line Plot for temperature over time
                    Chart(temperatureHistory) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Temperature", point.temperature)
                        )
                    }
                    .frame(height: 200)  // Set height for the chart
                }


                if !report.boardPowerSensors.isEmpty {
                    ForEach(report.boardPowerSensors.indices, id: \.self) { index in
                        let sensor = report.boardPowerSensors[index]
                        Text("Power Sensor \(sensor.name): \(sensor.voltage) volts")
                    }
                }


            }
        case .failure:
            Text("Creature has not had a health report yet")
        }

    }


    private func addTemperatureToHistory(_ temperature: Double) {
        let newPoint = TemperaturePoint(timestamp: Date(), temperature: temperature)
        temperatureHistory.append(newPoint)

        // Keep only the 100 most recent points
        if temperatureHistory.count > 100 {
            temperatureHistory.removeFirst(temperatureHistory.count - 100)
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

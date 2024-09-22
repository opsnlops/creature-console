import Charts
import Common
import Foundation
import OSLog
import SwiftUI

struct SensorData: View {

    var creature: Creature

    @State private var minTemperature = 60.0
    @State private var maxTemperature = 175.0
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

                    Gauge(value: report.boardTemperature, in: minTemperature...maxTemperature) {
                        Image(systemName: "thermometer.medium")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(report.boardTemperature))")
                            .foregroundColor(Color.blue)
                    } minimumValueLabel: {
                        Text("\(Int(minTemperature))")
                            .foregroundColor(Color.green)
                    } maximumValueLabel: {
                        Text("\(Int(maxTemperature))")
                            .foregroundColor(Color.red)
                    }

                    Gauge(value: report.boardTemperature, in: minTemperature...maxTemperature) {
                        Text("Temperature")
                    }
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
                        Gauge(value: sensor.voltage, in: 0...12) {
                            Text("Power Sensor \(sensor.name)")
                        }
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
    InputTable(creature: Creature.mock())
}

import Charts
import Common
import Foundation
import OSLog
import SwiftUI

struct SensorData: View {

    var creature: Creature
    var showTitle: Bool = true

    @State private var healthCacheState = CreatureHealthCacheState(
        motorSensorCache: [:], boardSensorCache: [:])
    @State private var showingHistoricalData = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private var shouldShowHistoricalData: Bool {
        #if os(tvOS)
            return false
        #else
            return true
        #endif
    }

    private var healthReport: Result<[BoardSensorReport], CacheError> {
        if let sensorData = healthCacheState.boardSensorCache[creature.id], !sensorData.isEmpty {
            return .success(sensorData.sorted(by: { $0.timestamp < $1.timestamp }))
        } else {
            return .failure(.noDataForCreature)
        }
    }

    var body: some View {
        Group {
            switch healthReport {
            case .success(let reports):
                if let latestReport = reports.last {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header with timestamp
                        if showTitle {
                            HStack {
                                Text("Sensor Data")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(
                                    "Last updated: \(dateFormatter.string(from: latestReport.timestamp))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }

                        // Critical metrics graphs
                        criticalMetricsGraphs(reports)

                        // Current sensor readings table
                        currentSensorTable(latestReport)

                        // Historical data toggle
                        if shouldShowHistoricalData && reports.count > 1 {
                            Button(action: {
                                showingHistoricalData.toggle()
                            }) {
                                HStack {
                                    Text("Historical Data (\(reports.count) readings)")
                                    Spacer()
                                    Image(
                                        systemName: showingHistoricalData
                                            ? "chevron.up" : "chevron.down")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)

                            if showingHistoricalData {
                                historicalDataTable(reports)
                            }
                        }
                    }
                } else {
                    emptyStateView()
                }
            case .failure:
                emptyStateView()
            }
        }
        .task {
            for await state in await CreatureHealthCache.shared.stateUpdates {
                await MainActor.run {
                    healthCacheState = state
                }
            }
        }
    }

    @ViewBuilder
    private func criticalMetricsGraphs(_ reports: [BoardSensorReport]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Critical Metrics")
                .font(.headline)

            HStack(spacing: 16) {
                // Board Temperature Graph
                VStack(alignment: .leading, spacing: 8) {
                    Text("Board Temperature (°F)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Chart(reports) { report in
                        LineMark(
                            x: .value("Time", report.timestamp),
                            y: .value("Temperature (°F)", report.boardTemperature)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary)
                            AxisValueLabel()
                                .foregroundStyle(.primary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary)
                            AxisValueLabel()
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(height: 120)
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }

                // Motor Power Graph (finding "Motor Power In" sensor)
                if let motorPowerData = extractMotorPowerData(from: reports) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Motor Power In (Watts)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Chart(motorPowerData) { dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.timestamp),
                                y: .value("Power (W)", dataPoint.power)
                            )
                            .foregroundStyle(.red)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(.secondary.opacity(0.3))
                                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(.secondary)
                                AxisValueLabel()
                                    .foregroundStyle(.primary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(.secondary.opacity(0.3))
                                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(.secondary)
                                AxisValueLabel()
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(height: 120)
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // Helper function to extract motor power data
    private func extractMotorPowerData(from reports: [BoardSensorReport]) -> [PowerDataPoint]? {
        var motorPowerData: [PowerDataPoint] = []

        for report in reports {
            // Look for motor power sensor with various possible names
            if let motorPowerSensor = report.powerReports.first(where: {
                $0.name.lowercased().contains("motor_power_in")
                    || $0.name.lowercased().contains("motor power in")
                    || $0.name.lowercased().contains("motor")
                        && $0.name.lowercased().contains("power")
            }) {
                motorPowerData.append(
                    PowerDataPoint(
                        timestamp: report.timestamp,
                        power: motorPowerSensor.power
                    ))
            }
        }

        return motorPowerData.isEmpty ? nil : motorPowerData
    }

    // Data model for power graph
    struct PowerDataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let power: Double
    }

    @ViewBuilder
    private func currentSensorTable(_ report: BoardSensorReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Readings")
                .font(.headline)

            VStack(spacing: 1) {
                // Header row
                HStack {
                    Text("Sensor")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Value")
                        .fontWeight(.medium)
                        .frame(width: 80, alignment: .trailing)
                    Text("Unit")
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))

                // Board temperature
                HStack {
                    Text("Board Temperature")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f", report.boardTemperature))
                        .foregroundColor(temperatureColor(report.boardTemperature))
                        .frame(width: 80, alignment: .trailing)
                    Text("°F")
                        .frame(width: 40, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))

                // Power sensors
                ForEach(report.powerReports.indices, id: \.self) { index in
                    let sensor = report.powerReports[index]

                    Group {
                        HStack {
                            Text("\(sensor.name) - Voltage")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.2f", sensor.voltage))
                                .foregroundColor(
                                    sensor.name.lowercased().contains("motor")
                                        ? motorVoltageColor(sensor.voltage)
                                        : sensor.name.lowercased().contains("3v3")
                                            ? v3v3Color(sensor.voltage)
                                            : voltageColor(sensor.voltage)
                                )
                                .frame(width: 80, alignment: .trailing)
                            Text("V")
                                .frame(width: 40, alignment: .leading)
                        }

                        HStack {
                            Text("\(sensor.name) - Current")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.3f", sensor.current))
                                .frame(width: 80, alignment: .trailing)
                            Text("A")
                                .frame(width: 40, alignment: .leading)
                        }

                        HStack {
                            Text("\(sensor.name) - Power")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.2f", sensor.power))
                                .frame(width: 80, alignment: .trailing)
                            Text("W")
                                .frame(width: 40, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func historicalDataTable(_ reports: [BoardSensorReport]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent History")
                .font(.headline)

            ScrollView {
                VStack(spacing: 1) {
                    // Header row
                    HStack {
                        Text("Time")
                            .fontWeight(.medium)
                            .frame(width: 100, alignment: .leading)
                        Text("Temp (°F)")
                            .fontWeight(.medium)
                            .frame(width: 80, alignment: .trailing)
                        Text("Power Sensors")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))

                    ForEach(reports.suffix(10).reversed(), id: \.timestamp) { report in
                        HStack(alignment: .top) {
                            Text(dateFormatter.string(from: report.timestamp))
                                .font(.caption)
                                .frame(width: 100, alignment: .leading)
                            Text(String(format: "%.1f", report.boardTemperature))
                                .font(.caption)
                                .foregroundColor(temperatureColor(report.boardTemperature))
                                .frame(width: 80, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(report.powerReports.indices, id: \.self) { index in
                                    let sensor = report.powerReports[index]
                                    Text(
                                        "\(sensor.name): \(String(format: "%.2f", sensor.voltage))V"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(
                                        sensor.name.lowercased().contains("motor")
                                            ? motorVoltageColor(sensor.voltage)
                                            : sensor.name.lowercased().contains("3v3")
                                                ? v3v3Color(sensor.voltage)
                                                : voltageColor(sensor.voltage)
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                    }
                }
            }
            .frame(maxHeight: 300)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("\(creature.name) has not sent sensor data yet")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Sensor data will appear here once the creature starts reporting")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // Helper functions for color coding
    private func temperatureColor(_ temperature: Double) -> Color {
        switch temperature {
        case ..<80: return .blue
        case 80..<100: return .green
        case 100..<125: return .orange
        default: return .red
        }
    }

    private func voltageColor(_ voltage: Double) -> Color {
        switch voltage {
        case ..<3.0: return .red
        case 3.0..<4.5: return .orange
        case 4.5..<5.5: return .green
        default: return .orange
        }
    }

    private func motorVoltageColor(_ voltage: Double) -> Color {
        switch voltage {
        case ..<7.0: return .red  // Below acceptable range
        case 7.0...8.8: return .green  // Acceptable range (7.0V - 8.4V)
        default: return .orange  // Above acceptable range
        }
    }

    private func v3v3Color(_ voltage: Double) -> Color {
        switch voltage {
        case ..<3.0: return .red  // Too low
        case 3.0...3.6: return .green  // Acceptable range (3.0V - 3.6V, target 3.3V)
        default: return .orange  // Too high
        }
    }
}

#Preview {
    SensorData(creature: Creature.mock())
}

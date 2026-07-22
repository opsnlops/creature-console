// SensorDataTables.swift
// Extracted from SensorData.swift (Phase 5 decomposition, issue #35).

import Charts
import Common
import Foundation
import SwiftUI

struct CriticalMetricsGraphs: View {
    let reports: [BoardSensorReport]

    var body: some View {
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
                if let motorPowerData = SensorDataLogic.extractMotorPowerData(from: reports) {
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
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct CurrentSensorTable: View {
    let report: BoardSensorReport

    var body: some View {
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
                        .frame(width: 60, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))

                // Board temperature
                HStack {
                    Text("Board Temperature")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f", report.boardTemperature))
                        .foregroundStyle(temperatureColor(report.boardTemperature))
                        .frame(width: 80, alignment: .trailing)
                    Text("°F")
                        .frame(width: 60, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))

                // Power sensors
                let sensors = filteredPowerSensors(report.powerReports)
                ForEach(sensors.indices, id: \.self) { index in
                    let sensor = sensors[index]

                    Group {
                        HStack {
                            Text("\(sensor.name) - Voltage")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.2f", sensor.voltage))
                                .foregroundStyle(
                                    sensor.name.lowercased().contains("motor")
                                        ? motorVoltageColor(sensor.voltage)
                                        : sensor.name.lowercased().contains("3v3")
                                            ? v3v3Color(sensor.voltage)
                                            : voltageColor(sensor.voltage)
                                )
                                .frame(width: 80, alignment: .trailing)
                            Text("V")
                                .frame(width: 60, alignment: .leading)
                        }

                        HStack {
                            Text("\(sensor.name) - Current")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.2f", sensor.current))
                                .frame(width: 80, alignment: .trailing)
                            Text("A")
                                .frame(width: 60, alignment: .leading)
                        }

                        HStack {
                            Text("\(sensor.name) - Power")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.2f", sensor.power))
                                .frame(width: 80, alignment: .trailing)
                            Text("W")
                                .frame(width: 60, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct DynamixelSensorTable: View {
    let report: DynamixelSensorReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dynamixel Servos")
                .font(.headline)

            VStack(spacing: 1) {
                // Header row
                HStack {
                    Text("DXL ID")
                        .fontWeight(.medium)
                        .frame(width: 70, alignment: .leading)
                    Text("Temp")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Load")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Position")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Voltage")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))

                let motors = report.motors.sorted(by: { $0.dxlId < $1.dxlId })
                ForEach(motors) { motor in
                    HStack {
                        Text("\(motor.dxlId)")
                            .frame(width: 70, alignment: .leading)
                        Text("\(String(format: "%.1f", motor.temperatureF)) °F")
                            .foregroundStyle(temperatureColor(motor.temperatureF))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("\(motor.presentLoad)")
                            .foregroundStyle(loadColor(motor.presentLoad))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        // Older controller firmware omits present_position; show "—" then.
                        Text(motor.presentPosition.map(String.init) ?? "—")
                            .foregroundStyle(motor.presentPosition == nil ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("\(String(format: "%.2f", motor.voltageV)) V")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct HistoricalDataTable: View {
    let reports: [BoardSensorReport]
    let dateFormatter: DateFormatter

    var body: some View {
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
                                .foregroundStyle(temperatureColor(report.boardTemperature))
                                .frame(width: 80, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                let sensors = filteredPowerSensors(report.powerReports)
                                ForEach(sensors.indices, id: \.self) { index in
                                    let sensor = sensors[index]
                                    Text(
                                        "\(sensor.name): \(String(format: "%.2f", sensor.voltage))V"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(
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
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
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

/// Color the present-load magnitude (raw signed Dynamixel units; ±1000 is roughly full scale).
private func loadColor(_ load: Int) -> Color {
    switch abs(load) {
    case ..<400: return .green
    case 400..<800: return .orange
    default: return .red
    }
}

private func v3v3Color(_ voltage: Double) -> Color {
    switch voltage {
    case ..<3.0: return .red  // Too low
    case 3.0...3.6: return .green  // Acceptable range (3.0V - 3.6V, target 3.3V)
    default: return .orange  // Too high
    }
}

private func filteredPowerSensors(_ sensors: [BoardPowerSensors]) -> [BoardPowerSensors] {
    #if os(tvOS)
        return sensors.filter { sensor in
            let name = sensor.name.lowercased()
            return !name.contains("vbus") && !name.contains("3v3")
        }
    #else
        return sensors
    #endif
}

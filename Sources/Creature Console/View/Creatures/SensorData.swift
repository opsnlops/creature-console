import Common
import Foundation
import OSLog
import SwiftUI

struct SensorData: View {

    var creature: Creature
    var showTitle: Bool = true

    @State private var healthCacheState = CreatureHealthCacheState(
        motorSensorCache: [:], dynamixelSensorCache: [:], boardSensorCache: [:])
    @State private var showingHistoricalData = false
    @State private var subscriptionTask: Task<Void, Never>?

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

    private var latestDynamixelReport: DynamixelSensorReport? {
        healthCacheState.dynamixelSensorCache[creature.id]?
            .max(by: { $0.timestamp < $1.timestamp })
    }

    private var hasAnyData: Bool {
        if case .success = healthReport { return true }
        return latestDynamixelReport != nil
    }

    /// The most recent timestamp across all sensor families we display.
    private var lastUpdated: Date? {
        var candidates: [Date] = []
        if case .success(let reports) = healthReport, let latest = reports.last {
            candidates.append(latest.timestamp)
        }
        if let dynamixel = latestDynamixelReport {
            candidates.append(dynamixel.timestamp)
        }
        return candidates.max()
    }

    var body: some View {
        Group {
            if hasAnyData {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with timestamp
                    if showTitle {
                        HStack {
                            Text("Sensor Data")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                            if let lastUpdated {
                                Text("Last updated: \(dateFormatter.string(from: lastUpdated))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Board sensors (temperature and power rails)
                    if case .success(let reports) = healthReport, let latestReport = reports.last {
                        // Critical metrics graphs
                        CriticalMetricsGraphs(reports: reports)

                        // Current sensor readings table
                        CurrentSensorTable(report: latestReport)

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
                            .foregroundStyle(.tint)

                            if showingHistoricalData {
                                HistoricalDataTable(reports: reports, dateFormatter: dateFormatter)
                            }
                        }
                    }

                    // Dynamixel servos
                    if let dynamixelReport = latestDynamixelReport, !dynamixelReport.motors.isEmpty
                    {
                        DynamixelSensorTable(report: dynamixelReport)
                    }
                }
            } else {
                emptyStateView()
            }
        }
        .onAppear {
            // Subscribe to cache updates (current state is sent immediately by the broadcaster)
            subscriptionTask = Task {
                for await state in await CreatureHealthCache.shared.stateUpdates {
                    healthCacheState = state
                }
            }
        }
        .onDisappear {
            subscriptionTask?.cancel()
            subscriptionTask = nil
        }
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(creature.name) has not sent sensor data yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Sensor data will appear here once the creature starts reporting")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#if DEBUG
    // Test-only helpers to expose private logic for unit tests
    extension SensorData {
        /// Wrapper that exposes the private motor power extraction logic to tests.
        func _test_extractMotorPowerData(from reports: [BoardSensorReport])
            -> [SensorPowerDataPoint]?
        {
            SensorDataLogic.extractMotorPowerData(from: reports)
        }
    }
#endif

#Preview {
    SensorData(creature: Creature.mock())
}

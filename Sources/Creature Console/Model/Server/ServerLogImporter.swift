import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor ServerLogImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "ServerLogImporter")

    // Keep more logs in the database than we display to allow for search/filtering
    private let maxLogEntries = 500

    // Add a single log entry (logs come in one at a time from the server)
    func addLog(_ dto: ServerLogItem) async throws {
        let logModel = ServerLogModel(dto: dto)
        modelContext.insert(logModel)
        try modelContext.save()
        try trimOldLogs()
    }

    // Remove the oldest logs once the table exceeds the max count. A COUNT query plus a
    // fetch limited to just the overflow keeps the steady-state cost per insert tiny —
    // never a full fetch+sort of the table — so this is safe to run on every insert.
    private func trimOldLogs() throws {
        let count = try modelContext.fetchCount(FetchDescriptor<ServerLogModel>())
        guard count > maxLogEntries else { return }

        var overflow = FetchDescriptor<ServerLogModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        overflow.fetchLimit = count - maxLogEntries
        let logsToDelete = try modelContext.fetch(overflow)
        for log in logsToDelete {
            modelContext.delete(log)
        }
        try modelContext.save()

        logger.trace("Trimmed \(logsToDelete.count) old log entries")
    }

    // Clear all logs
    func clearAllLogs() async throws {
        try modelContext.delete(model: ServerLogModel.self)
        try modelContext.save()
        logger.info("Cleared all log entries")
    }
}

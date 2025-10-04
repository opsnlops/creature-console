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

    // Track insert count to avoid trimming on every single log
    private var insertsSinceLastTrim = 0
    private let trimInterval = 50  // Only trim every N inserts

    // Add a single log entry (logs come in one at a time from the server)
    func addLog(_ dto: ServerLogItem) async throws {
        let logModel = ServerLogModel(dto: dto)
        modelContext.insert(logModel)

        insertsSinceLastTrim += 1

        // Only trim periodically, not on every insert
        if insertsSinceLastTrim >= trimInterval {
            try trimOldLogs()
            insertsSinceLastTrim = 0
        }

        try modelContext.save()
    }

    // Remove logs older than the max count
    private func trimOldLogs() throws {
        let descriptor = FetchDescriptor<ServerLogModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allLogs = try modelContext.fetch(descriptor)

        guard allLogs.count > maxLogEntries else { return }

        // Delete old logs beyond the max count
        let logsToDelete = Array(allLogs.dropFirst(maxLogEntries))
        for log in logsToDelete {
            modelContext.delete(log)
        }

        logger.trace("Trimmed \(logsToDelete.count) old log entries")
    }

    // Clear all logs
    func clearAllLogs() async throws {
        let descriptor = FetchDescriptor<ServerLogModel>()
        let allLogs = try modelContext.fetch(descriptor)

        try modelContext.transaction {
            for log in allLogs {
                modelContext.delete(log)
            }
        }

        try modelContext.save()
        logger.info("Cleared all log entries")
    }
}

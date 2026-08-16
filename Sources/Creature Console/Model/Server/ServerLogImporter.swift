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

    /// How long incoming lines pool before one batched save. Every ModelContext save re-runs
    /// every `@Query` in every visible view, so at log-burst rates per-line saves made
    /// glass-heavy views (the dialog editor especially) drag the whole UI (#74). Half a second
    /// of latency in the log window is invisible; a save per line is not.
    private let flushDelay: Duration = .milliseconds(500)

    private var pending: [ServerLogItem] = []
    private var flushTask: Task<Void, Never>?

    // Queue a single log entry (logs come in one at a time from the server) for the next
    // batched save. Save errors surface in the importer's own log, not to the caller —
    // the write happens after the caller has moved on.
    func addLog(_ dto: ServerLogItem) {
        pending.append(dto)
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: flushDelay)
            guard !Task.isCancelled else { return }
            do {
                try flush()
            } catch {
                logger.warning(
                    "Failed to save server logs to SwiftData: \(error.localizedDescription)")
            }
        }
    }

    /// Write everything queued right now: one insert per line, one save, one trim pass.
    func flush() throws {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        for dto in batch {
            modelContext.insert(ServerLogModel(dto: dto))
        }
        try modelContext.save()
        try trimOldLogs()
    }

    // Remove the oldest logs once the table exceeds the max count. A COUNT query plus a
    // fetch limited to just the overflow keeps the steady-state cost per flush tiny —
    // never a full fetch+sort of the table — so this is safe to run on every flush.
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

    // Clear all logs, including any still waiting for their batched save
    func clearAllLogs() async throws {
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll()
        try modelContext.delete(model: ServerLogModel.self)
        try modelContext.save()
        logger.info("Cleared all log entries")
    }
}

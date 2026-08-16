import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("ServerLogImporter operations")
struct ServerLogImporterTests {

    @Test("addLog + flush inserts new log entry")
    func addLogInsertsNew() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        let dto = ServerLogItem(
            timestamp: Date(),
            level: "INFO",
            message: "Test log message",
            logger_name: "TestLogger",
            thread_id: 12345
        )

        await importer.addLog(dto)
        try await importer.flush()

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.level == "INFO")
        #expect(results.first?.message == "Test log message")
        #expect(results.first?.loggerName == "TestLogger")
        #expect(results.first?.threadId == 12345)
    }

    @Test("flush writes every pooled line in one batch")
    func flushWritesPooledLines() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        for i in 0..<25 {
            let dto = ServerLogItem(
                timestamp: Date(),
                level: "INFO",
                message: "Log \(i)",
                logger_name: "TestLogger",
                thread_id: UInt32(i)
            )
            await importer.addLog(dto)
        }
        try await importer.flush()

        let context = ModelContext(container)
        let results = try context.fetch(FetchDescriptor<ServerLogModel>())
        #expect(results.count == 25)
    }

    @Test("pooled lines persist on their own without an explicit flush")
    func timedFlushPersistsWithoutExplicitFlush() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        let dto = ServerLogItem(
            timestamp: Date(),
            level: "INFO",
            message: "Eventually persisted",
            logger_name: "TestLogger",
            thread_id: 1
        )
        await importer.addLog(dto)

        // The timed flush fires after the importer's pooling delay; poll rather than
        // assuming an exact schedule.
        let context = ModelContext(container)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var results: [ServerLogModel] = []
        while ContinuousClock.now < deadline {
            results = try context.fetch(FetchDescriptor<ServerLogModel>())
            if !results.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(results.count == 1)
        #expect(results.first?.message == "Eventually persisted")
    }

    @Test("flush trims old logs when exceeding max count")
    func addLogTrimsOldLogs() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        // Add 502 logs (max is 500)
        let baseTime = Date()
        for i in 0..<502 {
            let dto = ServerLogItem(
                timestamp: baseTime.addingTimeInterval(TimeInterval(i)),
                level: "INFO",
                message: "Log \(i)",
                logger_name: "TestLogger",
                thread_id: UInt32(i)
            )
            await importer.addLog(dto)
        }
        try await importer.flush()

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let results = try context.fetch(fetchDescriptor)

        // Should be trimmed to 500
        #expect(results.count == 500)

        // The oldest logs should be removed, newest should remain
        // Most recent log should be "Log 501"
        #expect(results.first?.message == "Log 501")

        // Oldest remaining log should be "Log 2" (0 and 1 were trimmed)
        #expect(results.last?.message == "Log 2")
    }

    @Test("clearAllLogs removes all entries")
    func clearAllLogsRemovesAll() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        // Add some logs
        for i in 0..<10 {
            let dto = ServerLogItem(
                timestamp: Date(),
                level: "INFO",
                message: "Log \(i)",
                logger_name: "TestLogger",
                thread_id: UInt32(i)
            )
            await importer.addLog(dto)
        }
        try await importer.flush()

        // Verify logs were added
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        var results = try context.fetch(fetchDescriptor)
        #expect(results.count == 10)

        // Clear all logs
        try await importer.clearAllLogs()

        results = try context.fetch(fetchDescriptor)
        #expect(results.isEmpty)
    }

    @Test("clearAllLogs drops lines still pooled for the next flush")
    func clearAllLogsDropsPendingLines() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        let dto = ServerLogItem(
            timestamp: Date(),
            level: "INFO",
            message: "Pooled but cleared",
            logger_name: "TestLogger",
            thread_id: 1
        )
        await importer.addLog(dto)
        try await importer.clearAllLogs()
        try await importer.flush()

        let context = ModelContext(container)
        let results = try context.fetch(FetchDescriptor<ServerLogModel>())
        #expect(results.isEmpty)
    }

    @Test("clearAllLogs handles empty database")
    func clearAllLogsHandlesEmpty() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        // Should not throw on empty database
        try await importer.clearAllLogs()

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.isEmpty)
    }

    @Test("addLog maintains timestamp order")
    func addLogMaintainsOrder() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        let baseTime = Date()
        let timestamps = [
            baseTime.addingTimeInterval(-100),
            baseTime.addingTimeInterval(-50),
            baseTime,
            baseTime.addingTimeInterval(50),
        ]

        for (index, timestamp) in timestamps.enumerated() {
            let dto = ServerLogItem(
                timestamp: timestamp,
                level: "INFO",
                message: "Log \(index)",
                logger_name: "TestLogger",
                thread_id: UInt32(index)
            )
            await importer.addLog(dto)
        }
        try await importer.flush()

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 4)
        #expect(results[0].message == "Log 3")  // Most recent
        #expect(results[1].message == "Log 2")
        #expect(results[2].message == "Log 1")
        #expect(results[3].message == "Log 0")  // Oldest
    }

    @Test("addLog handles different log levels")
    func addLogHandlesDifferentLevels() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        let levels = ["TRACE", "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

        for (index, level) in levels.enumerated() {
            let dto = ServerLogItem(
                timestamp: Date(),
                level: level,
                message: "Message at \(level)",
                logger_name: "TestLogger",
                thread_id: UInt32(index)
            )
            await importer.addLog(dto)
        }
        try await importer.flush()

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 6)
        for level in levels {
            #expect(results.contains { $0.level == level })
        }
    }

    @Test("trimming only affects logs beyond max count")
    func trimmingAffectsOnlyOldLogs() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try makeTestModelContainer(schema: schema, configuration: config)

        let importer = ServerLogImporter(modelContainer: container)

        // Add exactly 500 logs (at the max)
        let baseTime = Date()
        for i in 0..<500 {
            let dto = ServerLogItem(
                timestamp: baseTime.addingTimeInterval(TimeInterval(i)),
                level: "INFO",
                message: "Log \(i)",
                logger_name: "TestLogger",
                thread_id: UInt32(i)
            )
            await importer.addLog(dto)
        }
        try await importer.flush()

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        var results = try context.fetch(fetchDescriptor)

        // Should have exactly 500
        #expect(results.count == 500)

        // Add one more - should trigger trimming
        let dto = ServerLogItem(
            timestamp: baseTime.addingTimeInterval(500),
            level: "INFO",
            message: "Log 500",
            logger_name: "TestLogger",
            thread_id: 500
        )
        await importer.addLog(dto)
        try await importer.flush()

        results = try context.fetch(fetchDescriptor)

        // Should still be 500 after trimming
        #expect(results.count == 500)

        // The newest log should be present
        #expect(results.contains { $0.message == "Log 500" })

        // The oldest log (Log 0) should be removed
        #expect(!results.contains { $0.message == "Log 0" })
    }
}

import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("ServerLogModel basics")
struct ServerLogModelTests {

    @Test("initializes with provided values")
    func initializesWithValues() throws {
        let timestamp = Date()
        let level = "INFO"
        let message = "Test log message"
        let loggerName = "TestLogger"
        let threadId: UInt32 = 12345

        let model = ServerLogModel(
            timestamp: timestamp,
            level: level,
            message: message,
            loggerName: loggerName,
            threadId: threadId
        )

        #expect(model.timestamp == timestamp)
        #expect(model.level == level)
        #expect(model.message == message)
        #expect(model.loggerName == loggerName)
        #expect(model.threadId == threadId)
    }

    @Test("converts from DTO")
    func convertsFromDTO() throws {
        let timestamp = Date()
        let dto = ServerLogItem(
            timestamp: timestamp,
            level: "ERROR",
            message: "DTO log message",
            logger_name: "DTOLogger",
            thread_id: 54321
        )

        let model = ServerLogModel(dto: dto)

        #expect(model.timestamp == dto.timestamp)
        #expect(model.level == dto.level)
        #expect(model.message == dto.message)
        #expect(model.loggerName == dto.logger_name)
        #expect(model.threadId == dto.thread_id)
    }

    @Test("converts to DTO")
    func convertsToDTO() throws {
        let timestamp = Date()
        let model = ServerLogModel(
            timestamp: timestamp,
            level: "WARNING",
            message: "Model log message",
            loggerName: "ModelLogger",
            threadId: 99999
        )

        let dto = model.toDTO()

        #expect(dto.timestamp == model.timestamp)
        #expect(dto.level == model.level)
        #expect(dto.message == model.message)
        #expect(dto.logger_name == model.loggerName)
        #expect(dto.thread_id == model.threadId)
    }

    @Test("round-trips through DTO conversion")
    func roundTripsDTO() throws {
        let timestamp = Date()
        let originalDTO = ServerLogItem(
            timestamp: timestamp,
            level: "INFO",
            message: "Round trip message",
            logger_name: "RoundTripLogger",
            thread_id: 77777
        )

        let model = ServerLogModel(dto: originalDTO)
        let convertedDTO = model.toDTO()

        #expect(convertedDTO.timestamp == originalDTO.timestamp)
        #expect(convertedDTO.level == originalDTO.level)
        #expect(convertedDTO.message == originalDTO.message)
        #expect(convertedDTO.logger_name == originalDTO.logger_name)
        #expect(convertedDTO.thread_id == originalDTO.thread_id)
    }

    @Test("persists in SwiftData context")
    func persistsInSwiftDataContext() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let timestamp = Date()
        let model = ServerLogModel(
            timestamp: timestamp,
            level: "ERROR",
            message: "Persist message",
            loggerName: "PersistLogger",
            threadId: 33333
        )

        context.insert(model)
        try context.save()

        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.level == "ERROR")
        #expect(results.first?.message == "Persist message")
        #expect(results.first?.loggerName == "PersistLogger")
        #expect(results.first?.threadId == 33333)
    }

    @Test("stores multiple log entries")
    func storesMultipleLogEntries() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let baseTime = Date()
        let logs = [
            ServerLogModel(
                timestamp: baseTime,
                level: "INFO",
                message: "First log",
                loggerName: "Logger1",
                threadId: 1
            ),
            ServerLogModel(
                timestamp: baseTime.addingTimeInterval(1),
                level: "WARNING",
                message: "Second log",
                loggerName: "Logger2",
                threadId: 2
            ),
            ServerLogModel(
                timestamp: baseTime.addingTimeInterval(2),
                level: "ERROR",
                message: "Third log",
                loggerName: "Logger3",
                threadId: 3
            ),
        ]

        for log in logs {
            context.insert(log)
        }
        try context.save()

        let fetchDescriptor = FetchDescriptor<ServerLogModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 3)
    }

    @Test("queries by log level")
    func queriesByLogLevel() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let baseTime = Date()
        let logs = [
            ServerLogModel(
                timestamp: baseTime,
                level: "INFO",
                message: "Info message",
                loggerName: "Logger",
                threadId: 1
            ),
            ServerLogModel(
                timestamp: baseTime.addingTimeInterval(1),
                level: "ERROR",
                message: "Error message 1",
                loggerName: "Logger",
                threadId: 2
            ),
            ServerLogModel(
                timestamp: baseTime.addingTimeInterval(2),
                level: "ERROR",
                message: "Error message 2",
                loggerName: "Logger",
                threadId: 3
            ),
        ]

        for log in logs {
            context.insert(log)
        }
        try context.save()

        let fetchDescriptor = FetchDescriptor<ServerLogModel>(
            predicate: #Predicate { $0.level == "ERROR" }
        )
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.level == "ERROR" })
    }

    @Test("queries by timestamp range")
    func queriesByTimestampRange() async throws {
        let schema = Schema([ServerLogModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let baseTime = Date()
        let logs = [
            ServerLogModel(
                timestamp: baseTime.addingTimeInterval(-100),
                level: "INFO",
                message: "Old log",
                loggerName: "Logger",
                threadId: 1
            ),
            ServerLogModel(
                timestamp: baseTime,
                level: "INFO",
                message: "Recent log 1",
                loggerName: "Logger",
                threadId: 2
            ),
            ServerLogModel(
                timestamp: baseTime.addingTimeInterval(10),
                level: "INFO",
                message: "Recent log 2",
                loggerName: "Logger",
                threadId: 3
            ),
        ]

        for log in logs {
            context.insert(log)
        }
        try context.save()

        let startTime = baseTime.addingTimeInterval(-10)
        let fetchDescriptor = FetchDescriptor<ServerLogModel>(
            predicate: #Predicate { $0.timestamp >= startTime }
        )
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.timestamp >= startTime })
    }

    @Test("handles different log levels")
    func handlesDifferentLogLevels() throws {
        let levels = ["TRACE", "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

        for level in levels {
            let model = ServerLogModel(
                timestamp: Date(),
                level: level,
                message: "Test message",
                loggerName: "Logger",
                threadId: 1
            )

            #expect(model.level == level)

            let dto = model.toDTO()
            #expect(dto.level == level)
        }
    }
}

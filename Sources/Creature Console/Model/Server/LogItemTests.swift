import Testing
import Foundation
import Common
@testable import Creature_Console

@Suite("LogItem")
struct LogItemTests {

    // MARK: - Helpers
    private func makeServerLog(
        level: String,
        message: String,
        loggerName: String = "Test.Logger",
        threadId: UInt32 = 123,
        timestamp: Date = Date()
    ) throws -> ServerLogItem {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = formatter.string(from: timestamp)

        let json = """
        {"timestamp":"\(iso)","level":"\(level)","message":"\(message)","logger_name":"\(loggerName)","thread_id":\(threadId)}
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = formatter.date(from: string) {
                return date
            }
            if let fallback = ISO8601DateFormatter().date(from: string) {
                return fallback
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return try decoder.decode(ServerLogItem.self, from: data)
    }

    // MARK: - Tests

    @Test("init(from:) maps all fields correctly and converts level")
    func mapsFieldsCorrectly() throws {
        let ts = Date(timeIntervalSince1970: 1_700_000_000) // fixed second precision to avoid fractional drift
        let server = try makeServerLog(level: "info", message: "Hello world", timestamp: ts)
        let local = LogItem(from: server)

        let delta = abs(local.timestamp.timeIntervalSince(ts))
        #expect(delta < 0.001)
        #expect(local.level == .info)
        #expect(local.message == "Hello world")
        #expect(local.logger_name == server.logger_name)
        #expect(local.thread_id == server.thread_id)
    }

    @Test("equatable compares IDs only")
    func equatableByIdOnly() throws {
        let serverA = try makeServerLog(level: "debug", message: "A")
        let serverB = try makeServerLog(level: "error", message: "B")

        var a = LogItem(from: serverA)
        var b = LogItem(from: serverB)

        // Different random ids by default -> not equal
        #expect(a != b)

        // Force the same id to validate equality semantics
        let sharedId = UUID()
        a.id = sharedId
        b.id = sharedId
        #expect(a == b)
    }

    @Test("Sendable conformance is valid")
    func sendableConformance() throws {
        func requiresSendable<T: Sendable>(_ value: T) { _ = value }
        let item = LogItem(from: try makeServerLog(level: "trace", message: "msg"))
        requiresSendable(item)
    }
}


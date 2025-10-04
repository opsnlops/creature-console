import Foundation

public struct ServerLogItem: Codable, Sendable {

    public var timestamp: Date
    public var level: String
    public var message: String
    public var logger_name: String
    public var thread_id: UInt32

    public init(
        timestamp: Date, level: String, message: String, logger_name: String, thread_id: UInt32
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.logger_name = logger_name
        self.thread_id = thread_id
    }

}

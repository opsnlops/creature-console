import Common
import Foundation

struct LogItem: Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var level: ServerLogLevel
    var message: String
    var logger_name: String
    var thread_id: UInt32

    static func == (lhs: LogItem, rhs: LogItem) -> Bool {
        return lhs.id == rhs.id
    }

    // Easy way to make one of these from the ServerLogItem class
    init(from: ServerLogItem) {
        self.timestamp = from.timestamp
        self.level = ServerLogLevel.init(from: from.level)
        self.message = from.message
        self.logger_name = from.logger_name
        self.thread_id = from.thread_id
    }
}

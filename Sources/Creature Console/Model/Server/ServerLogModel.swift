import Common
import Foundation
import SwiftData

/// SwiftData model for ServerLog
///
/// **IMPORTANT**: This model must stay in sync with `Common.ServerLogItem` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
@Model
final class ServerLogModel {
    var timestamp: Date = Date()
    var level: String = ""
    var message: String = ""
    var loggerName: String = ""
    var threadId: UInt32 = 0

    init(timestamp: Date, level: String, message: String, loggerName: String, threadId: UInt32) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.loggerName = loggerName
        self.threadId = threadId
    }
}

extension ServerLogModel {
    // Initialize from the Common DTO
    convenience init(dto: ServerLogItem) {
        self.init(
            timestamp: dto.timestamp,
            level: dto.level,
            message: dto.message,
            loggerName: dto.logger_name,
            threadId: dto.thread_id
        )
    }

    // Convert back to the Common DTO
    func toDTO() -> ServerLogItem {
        ServerLogItem(
            timestamp: self.timestamp,
            level: self.level,
            message: self.message,
            logger_name: self.loggerName,
            thread_id: self.threadId
        )
    }

    // Convert to LogItem for UI display
    func toLogItem() -> LogItem {
        LogItem(from: toDTO())
    }
}

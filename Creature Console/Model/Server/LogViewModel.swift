//
//  LogViewModel.swift
//  Creature Console
//
//  Created by April White on 4/15/23.
//

import Foundation
import SwiftUI
import SwiftProtobuf
import OSLog

class StopFlag {
    var shouldStop: Bool = false
}


/**
 Our local view of the Server_LogItem
 */
struct LogItem : CustomStringConvertible {
    var description: String {
    
        let time = humanReadableDate(from: self.timestamp)
        let level = humanReadableLogLevel(logLevel: self.level)
        
        return "[\(time)] [\(level)] \(message)"
        
    }
    
    
    let timestamp : Date
    let message : String
    let level : Server_LogLevel
    
    init(timestamp: Date, level: Server_LogLevel, message: String) {
        self.timestamp = timestamp
        self.message = message
        self.level = level
    }
    
    init(serverLogItem: Server_LogItem) {
        
        let seconds = TimeInterval(serverLogItem.timestamp.seconds)
        let nanoseconds = TimeInterval(serverLogItem.timestamp.nanos) / 1_000_000_000
        
        self.timestamp = Date(timeIntervalSince1970: seconds + nanoseconds)
        self.level = serverLogItem.level
        self.message = serverLogItem.message
    }

    func humanReadableDate(from date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS"
        return dateFormatter.string(from: date)
    }
    
    func humanReadableLogLevel(logLevel: Server_LogLevel) -> String {
        switch logLevel {
        case .trace:
            return "Trace"
        case .debug:
            return "Debug"
        case .info:
            return "Info"
        case .warn:
            return "Warn"
        case .error:
            return "Error"
        case .critical:
            return "Crtiical"
        case .unknown:
            return "Unknown"
        default:
            return "Undefined"
        }
    }
    
}

class LogViewModel: ObservableObject {
    @Published var logs: [LogItem] = []
    let stopFlag: StopFlag
    let maxBufferSize: Int
    let logFilter : Server_LogFilter
    let logger : Logger
        
    
    init(stopFlag: StopFlag, maxBufferSize: Int = 100, logFilter: Server_LogFilter)  {
        self.maxBufferSize = maxBufferSize
        self.stopFlag = stopFlag
        self.logFilter = logFilter
        self.logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "LogViewModel")
    }
    
    func addLogItem(_ serverLogItem: Server_LogItem) {
        if logs.count >= maxBufferSize {
            logs.removeFirst()
        }
        logs.append(LogItem(serverLogItem: serverLogItem))
    }
    
    func startStreaming(server: CreatureServerClient, logFilter: Server_LogFilter, stopFlag: StopFlag) async {
    
        logger.debug("starting log streaming")
        
        do {
            await server.streamLogs(logViewModel: self, logFilter: logFilter, stopFlag: stopFlag)
        }
        
        logger.debug("stopping log streaming")
        
    }
    
}





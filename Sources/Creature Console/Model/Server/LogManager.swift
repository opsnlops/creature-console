import Common
import SwiftUI

struct LogManagerState: Sendable {
    let logMessages: [LogItem]
}

actor LogManager {
    static let shared = LogManager()
    
    private var logMessages: [LogItem] = []
    private var serverLogsScrollBackLines: Int = 100
    
    private let (stateStream, stateContinuation) = AsyncStream.makeStream(of: LogManagerState.self)
    var stateUpdates: AsyncStream<LogManagerState> { 
        publishState() // Ensure initial state is published
        return stateStream 
    }
    
    private init() {
        // Initial state will be published on first access to stateUpdates
    }
    
    private func publishState() {
        let currentState = LogManagerState(logMessages: logMessages)
        stateContinuation.yield(currentState)
    }
    
    func setScrollBackLines(_ lines: Int) {
        serverLogsScrollBackLines = lines
    }
    
    func addLogMessage(_ logItem: LogItem) {
        logMessages.append(logItem)
        if logMessages.count > serverLogsScrollBackLines {
            logMessages.removeFirst()
        }
        publishState()
    }
    
    func addLogMessage(from serverLogItem: ServerLogItem) {
        let logItem = LogItem(from: serverLogItem)
        addLogMessage(logItem)
    }

    func getCurrentState() -> LogManagerState {
        return LogManagerState(logMessages: logMessages)
    }
}

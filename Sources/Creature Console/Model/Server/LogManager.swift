import Common
import SwiftUI

struct LogManagerState: Sendable {
    let logMessages: [LogItem]
}

actor LogManager {
    static let shared = LogManager()

    private var logMessages: [LogItem] = []
    private var serverLogsScrollBackLines: Int = 100

    // Broadcasting AsyncStream for UI updates
    private var subscribers: [UUID: AsyncStream<LogManagerState>.Continuation] = [:]

    var stateUpdates: AsyncStream<LogManagerState> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[id] = continuation

            // Send current state immediately to new subscriber
            let currentState = LogManagerState(logMessages: logMessages)
            continuation.yield(currentState)

            continuation.onTermination = { @Sendable _ in
                Task { [id] in
                    await self.removeSubscriber(id)
                }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private init() {
        // Initial state will be published on first access to stateUpdates
    }

    private func publishState() {
        let currentState = LogManagerState(logMessages: logMessages)

        // Broadcast to all active subscribers
        for continuation in subscribers.values {
            continuation.yield(currentState)
        }
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

import Combine
import Common
import SwiftUI

class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logMessages: [LogItem] = []

    @AppStorage("serverLogsScrollBackLines") var serverLogsScrollBackLines = 100

    private var cancellables = Set<AnyCancellable>()

    func addLogMessage(_ logItem: LogItem) {
        DispatchQueue.main.async {
            self.logMessages.append(logItem)
            if self.logMessages.count > self.serverLogsScrollBackLines {
                self.logMessages.removeFirst()
            }
        }
    }

    func addLogMessage(from serverLogItem: ServerLogItem) {
        let logItem = LogItem(from: serverLogItem)
        addLogMessage(logItem)
    }
}

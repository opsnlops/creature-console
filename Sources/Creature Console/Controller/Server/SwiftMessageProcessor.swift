import Common
import Foundation
import OSLog

/// A simple `MessageProcessor` that prints things to the screen for debugging
class SwiftMessageProcessor: MessageProcessor, ObservableObject {

    // Yes! It singletons!
    static let shared = SwiftMessageProcessor()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SwiftMessageProcessor")

    // Bad things would happen if more than one of these exists
    private init() {
        logger.info("Swift-based MessageProcessor created")
    }

    func processNotice(_ notice: Notice) {
        logger.notice(
            "[NOTICE] [\(TimeHelper.formatToLocalTime(notice.timestamp))] \(notice.message)")
    }

    func processLog(_ logItem: ServerLogItem) {
        ServerLogItemProcessor.processServerLogItem(logItem)
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        SystemCountersItemProcessor.processSystemCounters(counters)
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        VirtualStatusLightsProcessor.processVirtualStatusLights(statusLights)
    }
}

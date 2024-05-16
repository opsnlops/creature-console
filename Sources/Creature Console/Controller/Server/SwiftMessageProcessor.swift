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
        logger.debug(
            "[COUNTERS] Server is on frame \(counters.totalFrames)! \(counters.framesStreamed) frames have been streamed."
        )
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        logger.info(
            "[STATUS LIGHTS] running: \(statusLights.running ? "on" : "off"), streaming: \(statusLights.streaming ? "on" : "off"), DMX: \(statusLights.dmx ? "on" : "off")"
        )
    }
}

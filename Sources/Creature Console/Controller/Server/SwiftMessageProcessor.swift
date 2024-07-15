import Common
import Foundation
import OSLog

/// The Swift version of our `MessageProcessor`
class SwiftMessageProcessor: MessageProcessor, ObservableObject {

    // Yes! It singletons!
    static let shared = SwiftMessageProcessor()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SwiftMessageProcessor")

    // Bad things would happen if more than one of these exists
    private init() {
        logger.info("Swift-based MessageProcessor created")
    }

    func processNotice(_ notice: Notice) {
        NoticeMessageProcessor.processNotice(notice)
    }

    func processLog(_ logItem: ServerLogItem) {
        ServerLogItemProcessor.processServerLogItem(logItem)
    }

    func processSensorReport(_ sensorReport: SensorReport) {
        SensorReportMessageProcessor.processSensorReport(sensorReport)
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        SystemCountersItemProcessor.processSystemCounters(counters)
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        VirtualStatusLightsProcessor.processVirtualStatusLights(statusLights)
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) {
        // nop
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) {
        CacheInvalidationProcessor.processCacheInvalidation(cacheInvalidation)
    }
}

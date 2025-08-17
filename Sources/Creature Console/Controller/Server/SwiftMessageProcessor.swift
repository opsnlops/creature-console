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

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {
        BoardSensorReportMessageProcessor.processBoardSensorReport(boardSensorReport)
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) {
        CacheInvalidationProcessor.processCacheInvalidation(cacheInvalidation)
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        EmergencyStopMessageProcessor.processEmergencyStop(emergencyStop)
    }

    func processLog(_ logItem: ServerLogItem) {
        ServerLogItemProcessor.processServerLogItem(logItem)
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) {
        MotorSensorReportMessageProcessor.processMotorSensorReport(motorSensorReport)
    }

    func processNotice(_ notice: Notice) {
        NoticeMessageProcessor.processNotice(notice)
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) {
        // nop
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        VirtualStatusLightsProcessor.processVirtualStatusLights(statusLights)
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        SystemCountersItemProcessor.processSystemCounters(counters)
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) {
        logger.info(
            "Watchdog warning received: \(watchdogWarning.warningType) - \(watchdogWarning.currentValue)/\(watchdogWarning.threshold)"
        )
    }
}

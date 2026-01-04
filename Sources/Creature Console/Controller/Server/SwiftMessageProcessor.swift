import Common
import Foundation
import OSLog
import PlaylistRuntime

/// The Swift version of our `MessageProcessor`
final class SwiftMessageProcessor: MessageProcessor, ObservableObject {

    // Yes! It singletons!
    static let shared = SwiftMessageProcessor()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SwiftMessageProcessor")

    // Bad things would happen if more than one of these exists
    private init() {
        logger.debug("Swift-based MessageProcessor created")
    }

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {
        logger.debug(
            "SwiftMessageProcessor: Processing board sensor report for creature \(boardSensorReport.creatureId)"
        )
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
        PlaylistRuntimeChannel.handle(status: playlistStatus)
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        VirtualStatusLightsProcessor.processVirtualStatusLights(statusLights)
    }

    func processSystemCounters(_ counters: ServerCountersPayload) {
        SystemCountersItemProcessor.processSystemCounters(counters)
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) {
        logger.info(
            "Watchdog warning received: \(watchdogWarning.warningType) - \(watchdogWarning.currentValue)/\(watchdogWarning.threshold)"
        )
    }

    func processJobProgress(_ jobProgress: JobProgress) {
        JobStatusMessageProcessor.processJobProgress(jobProgress)
    }

    func processJobComplete(_ jobComplete: JobCompletion) {
        JobStatusMessageProcessor.processJobCompletion(jobComplete)
    }

    func processIdleStateChanged(_ idleState: IdleStateChanged) {
        logger.info(
            "Idle state changed for \(idleState.creatureId): \(idleState.idleEnabled ? "enabled" : "disabled")"
        )
        Task { @MainActor in
            SystemCountersStore.shared.updateRuntimeState(
                creatureId: idleState.creatureId,
                idleEnabled: idleState.idleEnabled
            )
            NotificationCenter.default.post(
                name: Notification.Name("IdleStateChanged"),
                object: idleState
            )
        }
    }

    func processCreatureActivity(_ activity: CreatureActivity) {
        logger.debug(
            "Activity update for \(activity.creatureId): state=\(activity.state.rawValue) anim=\(activity.animationId ?? "none") session=\(activity.sessionId ?? "n/a") reason=\(activity.reason?.rawValue ?? "unknown")"
        )
        Task { @MainActor in
            SystemCountersStore.shared.updateRuntimeActivity(
                creatureId: activity.creatureId,
                activity: CreatureRuntimeActivity(
                    state: activity.state,
                    animationId: activity.animationId,
                    sessionId: activity.sessionId,
                    reason: activity.reason,
                    startedAt: nil,
                    updatedAt: nil
                )
            )
            NotificationCenter.default.post(
                name: Notification.Name("CreatureActivityUpdated"),
                object: activity
            )
        }
    }
}

import Common
import Foundation
import OSLog
import PlaylistRuntime

/// The Swift version of our `MessageProcessor`
final class SwiftMessageProcessor: MessageProcessor {

    // Yes! It singletons!
    static let shared = SwiftMessageProcessor()

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SwiftMessageProcessor")

    // Bad things would happen if more than one of these exists
    private init() {
        logger.debug("Swift-based MessageProcessor created")
    }

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) async {
        logger.debug(
            "SwiftMessageProcessor: Processing board sensor report for creature \(boardSensorReport.creatureId)"
        )
        await BoardSensorReportMessageProcessor.processBoardSensorReport(boardSensorReport)
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) async {
        CacheInvalidationProcessor.process(cacheInvalidation)
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) async {
        await EmergencyStopMessageProcessor.processEmergencyStop(emergencyStop)
    }

    func processLog(_ logItem: ServerLogItem) async {
        await ServerLogItemProcessor.processServerLogItem(logItem)
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) async {
        await MotorSensorReportMessageProcessor.processMotorSensorReport(motorSensorReport)
    }

    func processDynamixelSensorReport(_ dynamixelSensorReport: DynamixelSensorReport) async {
        await DynamixelSensorReportMessageProcessor.processDynamixelSensorReport(
            dynamixelSensorReport)
    }

    func processNotice(_ notice: Notice) async {
        await NoticeMessageProcessor.processNotice(notice)
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) async {
        PlaylistRuntimeChannel.handle(status: playlistStatus)
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) async {
        await VirtualStatusLightsProcessor.processVirtualStatusLights(statusLights)
    }

    func processSystemCounters(_ counters: ServerCountersPayload) async {
        await SystemCountersItemProcessor.processSystemCounters(counters)
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) async {
        logger.info(
            "Watchdog warning received: \(watchdogWarning.warningType) - \(watchdogWarning.currentValue)/\(watchdogWarning.threshold)"
        )
    }

    func processJobProgress(_ jobProgress: JobProgress) async {
        await JobStatusMessageProcessor.processJobProgress(jobProgress)
    }

    func processJobComplete(_ jobComplete: JobCompletion) async {
        await JobStatusMessageProcessor.processJobCompletion(jobComplete)
    }

    func processIdleStateChanged(_ idleState: IdleStateChanged) async {
        logger.info(
            "Idle state changed for \(idleState.creatureId): \(idleState.idleEnabled ? "enabled" : "disabled")"
        )
        await MainActor.run {
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

    func processCreatureActivity(_ activity: CreatureActivity) async {
        logger.debug(
            "Activity update for \(activity.creatureId): state=\(activity.state.rawValue) anim=\(activity.animationId ?? "none") session=\(activity.sessionId ?? "n/a") reason=\(activity.reason?.rawValue ?? "unknown")"
        )
        await MainActor.run {
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

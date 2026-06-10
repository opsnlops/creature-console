import Common
import Foundation
import PlaylistRuntime

final class LightweightMessageProcessor: MessageProcessor {
    static let shared = LightweightMessageProcessor()

    private let jobStore: LightweightJobStore
    private let healthStore: LightweightHealthStore

    init(
        jobStore: LightweightJobStore = .shared,
        healthStore: LightweightHealthStore = .shared
    ) {
        self.jobStore = jobStore
        self.healthStore = healthStore
    }

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) async {
        await healthStore.record(boardReport: boardSensorReport)
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) async {
        // Not needed in lightweight client
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) async {
        // Not needed in lightweight client
    }

    func processLog(_ logItem: ServerLogItem) async {
        // Not needed in lightweight client
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) async {
        // Not needed for current health display
    }

    func processNotice(_ notice: Notice) async {
        // Not needed
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) async {
        PlaylistRuntimeChannel.handle(status: playlistStatus)
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) async {
        // Not needed
    }

    func processSystemCounters(_ counters: ServerCountersPayload) async {
        // Not needed
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) async {
        // Not needed
    }

    func processJobProgress(_ jobProgress: JobProgress) async {
        await jobStore.update(with: jobProgress)
    }

    func processJobComplete(_ jobComplete: JobCompletion) async {
        await jobStore.update(with: jobComplete)
    }

    func processIdleStateChanged(_ idleState: IdleStateChanged) async {
        // Not needed for lightweight client today
    }

    func processCreatureActivity(_ activity: CreatureActivity) async {
        // Not needed for lightweight client today
    }
}

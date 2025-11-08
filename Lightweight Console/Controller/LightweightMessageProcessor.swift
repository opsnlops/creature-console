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

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {
        Task {
            await healthStore.record(boardReport: boardSensorReport)
        }
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) {
        // Not needed in lightweight client
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        // Not needed in lightweight client
    }

    func processLog(_ logItem: ServerLogItem) {
        // Not needed in lightweight client
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) {
        // Not needed for current health display
    }

    func processNotice(_ notice: Notice) {
        // Not needed
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) {
        PlaylistRuntimeChannel.handle(status: playlistStatus)
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        // Not needed
    }

    func processSystemCounters(_ counters: SystemCountersDTO) {
        // Not needed
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) {
        // Not needed
    }

    func processJobProgress(_ jobProgress: JobProgress) {
        Task {
            await jobStore.update(with: jobProgress)
        }
    }

    func processJobComplete(_ jobComplete: JobCompletion) {
        Task {
            await jobStore.update(with: jobComplete)
        }
    }
}

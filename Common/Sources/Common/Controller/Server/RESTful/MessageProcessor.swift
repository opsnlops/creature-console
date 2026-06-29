import Foundation

/// This protocol provides a way to abstract out the message processor for the web socket
///
/// Methods are `async` and are awaited one at a time by the websocket client's ingestion
/// pipeline, so messages are always processed in the exact order they arrived from the
/// server. Implementations that kick off long-running work (network calls, cache rebuilds)
/// should still return quickly and let that work run in its own task.
public protocol MessageProcessor: Sendable {
    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) async
    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) async
    func processEmergencyStop(_ emergencyStop: EmergencyStop) async
    func processLog(_ logItem: ServerLogItem) async
    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) async
    func processDynamixelSensorReport(_ dynamixelSensorReport: DynamixelSensorReport) async
    func processNotice(_ notice: Notice) async
    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) async
    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) async
    func processSystemCounters(_ counters: ServerCountersPayload) async
    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) async
    func processJobProgress(_ jobProgress: JobProgress) async
    func processJobComplete(_ jobComplete: JobCompletion) async
    func processIdleStateChanged(_ idleState: IdleStateChanged) async
    func processCreatureActivity(_ activity: CreatureActivity) async
}

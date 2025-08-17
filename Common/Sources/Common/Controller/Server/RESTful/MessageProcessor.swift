import Foundation

/// This protocol provides a way to abstract out the message processor for the web socket
public protocol MessageProcessor {
    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport)
    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation)
    func processEmergencyStop(_ emergencyStop: EmergencyStop)
    func processLog(_ logItem: ServerLogItem)
    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport)
    func processNotice(_ notice: Notice)
    func processPlaylistStatus(_ playlistStatus: PlaylistStatus)
    func processStatusLights(_ statusLights: VirtualStatusLightsDTO)
    func processSystemCounters(_ counters: SystemCountersDTO)
    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning)
}

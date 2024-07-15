import Foundation

/// This protocol provides a way to abstract out the message processor for the web socket
public protocol MessageProcessor {
    func processNotice(_ notice: Notice)
    func processLog(_ logItem: ServerLogItem)
    func processSystemCounters(_ counters: SystemCountersDTO)
    func processStatusLights(_ statusLights: VirtualStatusLightsDTO)
    func processSensorReport(_ sensorReport: SensorReport)
    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation)
    func processPlaylistStatus(_ playlistStatus: PlaylistStatus)
}

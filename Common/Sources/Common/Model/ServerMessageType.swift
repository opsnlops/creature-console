import Foundation

/// A simple enum to keep track of the various messages that might be coming in from the server
public enum ServerMessageType: String {
    case serverCounters = "server-counters"
    case logging = "log"
    case notice = "notice"
    case statusLights = "status-lights"
    case streamFrame = "stream-frame"
    case motorSensorReport = "motor-sensor-report"
    case boardSensorReport = "board-sensor-report"
    case cacheInvalidation = "cache-invalidation"
    case playlistStatus = "playlist-status"
    case unknown

    public init(from command: String) {
        self = ServerMessageType(rawValue: command) ?? .unknown
    }
}

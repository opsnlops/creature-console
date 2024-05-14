import Foundation

/// A simple enum to keep track of the various messages that might be coming in from the server
public enum ServerMessageType: String {
    case serverCounters = "server-counters"
    case logging = "log"
    case notice = "notice"
    case statusLights = "status-lights"
    case streamFrame = "stream-frame"
    case unknown

    public init(from command: String) {
        self = ServerMessageType(rawValue: command) ?? .unknown
    }
}

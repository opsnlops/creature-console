
import Foundation

/**
 A simple enum to keep track of the various messages that might be coming in from the server
 */
enum ServerMessageType: String {
    case serverCounters = "server-counters"
    case database = "database"
    case logging = "log"
    case notice = "notice"
    case unknown

    init(from command: String) {
        self = ServerMessageType(rawValue: command) ?? .unknown
    }
}
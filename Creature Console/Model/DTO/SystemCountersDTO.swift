
import Foundation


/**
 Super simple view of the system counters from the server
 */
struct SystemCountersDTO : Decodable {

    var totalFrames: UInt64
    var eventsProcessed: UInt64
    var framesStreamed: UInt64
    var dmxEventsProcessed: UInt64
    var animationsPlayed: UInt64
    var soundsPlayed: UInt64
    var playlistsStarted: UInt64
    var playlistsStopped: UInt64
    var playlistsEventsProcessed: UInt64
    var playlistStatusRequests: UInt64
    var restRequestsProcessed: UInt64

}

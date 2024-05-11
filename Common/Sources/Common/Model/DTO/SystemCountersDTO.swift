
import Foundation


/**
 Super simple view of the system counters from the server
 */
public struct SystemCountersDTO : Decodable {

    public var totalFrames: UInt64
    public var eventsProcessed: UInt64
    public var framesStreamed: UInt64
    public var dmxEventsProcessed: UInt64
    public var animationsPlayed: UInt64
    public var soundsPlayed: UInt64
    public var playlistsStarted: UInt64
    public var playlistsStopped: UInt64
    public var playlistsEventsProcessed: UInt64
    public var playlistStatusRequests: UInt64
    public var restRequestsProcessed: UInt64

}

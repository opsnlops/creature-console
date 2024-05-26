/// Super simple view of the system counters from the server
public struct VirtualStatusLightsDTO: Codable {

    public var running: Bool
    public var dmx: Bool
    public var streaming: Bool
    public var animation_playing: Bool

}

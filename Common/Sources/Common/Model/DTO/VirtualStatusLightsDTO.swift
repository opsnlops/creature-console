/// Super simple view of the system counters from the server
public struct VirtualStatusLightsDTO: Decodable {

    public var running: Bool
    public var dmx: Bool
    public var streaming: Bool

}

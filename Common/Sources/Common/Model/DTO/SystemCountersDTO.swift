import Foundation

public struct SystemCountersDTO: Codable, Sendable, Equatable {
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
    public var websocketConnectionsProcessed: UInt64
    public var websocketMessagesReceived: UInt64
    public var websocketMessagesSent: UInt64
    public var websocketPingsSent: UInt64
    public var websocketPongsReceived: UInt64

    public init(
        totalFrames: UInt64 = 0,
        eventsProcessed: UInt64 = 0,
        framesStreamed: UInt64 = 0,
        dmxEventsProcessed: UInt64 = 0,
        animationsPlayed: UInt64 = 0,
        soundsPlayed: UInt64 = 0,
        playlistsStarted: UInt64 = 0,
        playlistsStopped: UInt64 = 0,
        playlistsEventsProcessed: UInt64 = 0,
        playlistStatusRequests: UInt64 = 0,
        restRequestsProcessed: UInt64 = 0,
        websocketConnectionsProcessed: UInt64 = 0,
        websocketMessagesReceived: UInt64 = 0,
        websocketMessagesSent: UInt64 = 0,
        websocketPingsSent: UInt64 = 0,
        websocketPongsReceived: UInt64 = 0
    ) {
        self.totalFrames = totalFrames
        self.eventsProcessed = eventsProcessed
        self.framesStreamed = framesStreamed
        self.dmxEventsProcessed = dmxEventsProcessed
        self.animationsPlayed = animationsPlayed
        self.soundsPlayed = soundsPlayed
        self.playlistsStarted = playlistsStarted
        self.playlistsStopped = playlistsStopped
        self.playlistsEventsProcessed = playlistsEventsProcessed
        self.playlistStatusRequests = playlistStatusRequests
        self.restRequestsProcessed = restRequestsProcessed
        self.websocketConnectionsProcessed = websocketConnectionsProcessed
        self.websocketMessagesReceived = websocketMessagesReceived
        self.websocketMessagesSent = websocketMessagesSent
        self.websocketPingsSent = websocketPingsSent
        self.websocketPongsReceived = websocketPongsReceived
    }
}

public struct ServerCountersRuntimeState: Codable, Sendable, Equatable {
    public let creatureId: String
    public let runtime: CreatureRuntime?

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case runtime
    }

    public init(creatureId: String, runtime: CreatureRuntime?) {
        self.creatureId = creatureId
        self.runtime = runtime
    }
}

public struct ServerCountersPayload: Codable, Sendable, Equatable {
    public let counters: SystemCountersDTO
    public let runtimeStates: [ServerCountersRuntimeState]

    enum CodingKeys: String, CodingKey {
        case counters
        case runtimeStates = "runtime_states"
    }

    public init(
        counters: SystemCountersDTO = SystemCountersDTO(),
        runtimeStates: [ServerCountersRuntimeState] = []
    ) {
        self.counters = counters
        self.runtimeStates = runtimeStates
    }
}

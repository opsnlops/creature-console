import Common
import SwiftUI


public class SystemCountersStore: ObservableObject {
    public static let shared = SystemCountersStore()

    @Published public var systemCounters: SystemCountersDTO

    private init(systemCounters: SystemCountersDTO = SystemCountersDTO()) {
        self.systemCounters = systemCounters
    }

    // Convenience methods to update specific properties
    public func updateTotalFrames(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.totalFrames = value
        }
    }

    public func updateEventsProcessed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.eventsProcessed = value
        }
    }

    public func updateFramesStreamed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.framesStreamed = value
        }
    }

    public func updateDmxEventsProcessed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.dmxEventsProcessed = value
        }
    }

    public func updateAnimationsPlayed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.animationsPlayed = value
        }
    }

    public func updateSoundsPlayed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.soundsPlayed = value
        }
    }

    public func updatePlaylistsStarted(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.playlistsStarted = value
        }
    }

    public func updatePlaylistsStopped(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.playlistsStopped = value
        }
    }

    public func updatePlaylistsEventsProcessed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.playlistsEventsProcessed = value
        }
    }

    public func updatePlaylistStatusRequests(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.playlistStatusRequests = value
        }
    }

    public func updateRestRequestsProcessed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.restRequestsProcessed = value
        }
    }

    public func updateWebsocketConnectionsProcessed(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.websocketConnectionsProcessed = value
        }
    }

    public func updateWebsocketMessagesReceived(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.websocketMessagesReceived = value
        }
    }

    public func updateWebsocketMessagesSent(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.websocketMessagesSent = value
        }
    }

    public func updateWebsocketPingsSent(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.websocketPingsSent = value
        }
    }

    public func updateWebsocketPongsReceived(_ value: UInt64) {
        DispatchQueue.main.async {
            self.systemCounters.websocketPongsReceived = value
        }
    }

    // New update method to update all counters at once
    public func update(with newCounters: SystemCountersDTO) {
        DispatchQueue.main.async {
            self.systemCounters = newCounters
        }
    }
}


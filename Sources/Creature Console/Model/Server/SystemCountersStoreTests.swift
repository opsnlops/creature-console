import Testing
import Foundation
import Common
@testable import Creature_Console

@Suite("SystemCountersStore")
struct SystemCountersStoreTests {

    // Each test uses an isolated instance to avoid cross-test interference from the singleton
    private func makeIsolatedStore() async -> SystemCountersStore {
        await MainActor.run { SystemCountersStore.makeForTesting() }
    }

    @Test("default store starts with zeroed counters")
    func defaultZeroedCounters() async throws {
        let store = await makeIsolatedStore()
        let counters = await MainActor.run { store.systemCounters }
        let runtimeStates = await MainActor.run { store.runtimeStates }
        #expect(counters.totalFrames == 0)
        #expect(counters.eventsProcessed == 0)
        #expect(counters.framesStreamed == 0)
        #expect(runtimeStates.isEmpty)
    }

    @Test("update replaces the entire counters value")
    func updateReplacesCounters() async throws {
        let store = await makeIsolatedStore()
        let newCounters = SystemCountersDTO(
            totalFrames: 123,
            eventsProcessed: 5,
            framesStreamed: 9,
            dmxEventsProcessed: 2,
            animationsPlayed: 1,
            soundsPlayed: 3,
            playlistsStarted: 4,
            playlistsStopped: 1,
            playlistsEventsProcessed: 6,
            playlistStatusRequests: 7,
            restRequestsProcessed: 8,
            websocketConnectionsProcessed: 10,
            websocketMessagesReceived: 11,
            websocketMessagesSent: 12,
            websocketPingsSent: 13,
            websocketPongsReceived: 14
        )

        let payload = ServerCountersPayload(
            counters: newCounters,
            runtimeStates: [ServerCountersRuntimeState(creatureId: "creature-1", runtime: nil)]
        )

        await MainActor.run { store.update(with: payload) }

        let current = await MainActor.run { store.systemCounters }
        let runtimeStates = await MainActor.run { store.runtimeStates }
        #expect(current.totalFrames == 123)
        #expect(current.websocketPongsReceived == 14)
        #expect(current.framesStreamed == 9)
        #expect(runtimeStates.count == 1)
        #expect(runtimeStates.first?.creatureId == "creature-1")
    }

    @Test("update can be called from a background context and applies on main")
    func updateFromBackground() async throws {
        let store = await makeIsolatedStore()
        let newCounters = SystemCountersDTO(totalFrames: 777)
        let payload = ServerCountersPayload(
            counters: newCounters,
            runtimeStates: [ServerCountersRuntimeState(creatureId: "rt-1", runtime: nil)]
        )

        // Invoke update from a non-main context; actor hop will occur as needed
        await Task.detached {
            await store.update(with: payload)
        }.value

        let current = await MainActor.run { store.systemCounters }
        let runtimeStates = await MainActor.run { store.runtimeStates }
        #expect(current.totalFrames == 777)
        #expect(runtimeStates.map(\.creatureId) == ["rt-1"])
    }
}

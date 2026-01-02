import Common
import SwiftUI

/// Wrapper around the SystemCountersDTO to allow for it to be observed and updated properly
@MainActor
public class SystemCountersStore: ObservableObject {
    public static let shared = SystemCountersStore()

    @Published public var systemCounters: SystemCountersDTO
    @Published public var runtimeStates: [ServerCountersRuntimeState]

    private init(
        systemCounters: SystemCountersDTO = SystemCountersDTO(),
        runtimeStates: [ServerCountersRuntimeState] = []
    ) {
        self.systemCounters = systemCounters
        self.runtimeStates = runtimeStates
    }

#if DEBUG
    /// Create an independent store instance for tests without touching the shared singleton.
    public static func makeForTesting(
        initial: SystemCountersDTO = SystemCountersDTO(),
        runtimeStates: [ServerCountersRuntimeState] = []
    ) -> SystemCountersStore {
        return SystemCountersStore(systemCounters: initial, runtimeStates: runtimeStates)
    }
#endif

    // Update all of the counters at once
    public func update(with payload: ServerCountersPayload) {
        self.systemCounters = payload.counters
        self.runtimeStates = payload.runtimeStates
    }

    public func updateRuntimeState(creatureId: String, idleEnabled: Bool) {
        guard let index = runtimeStates.firstIndex(where: { $0.creatureId == creatureId }) else {
            return
        }
        guard let existing = runtimeStates[index].runtime else { return }
        let updatedRuntime = CreatureRuntime(
            idleEnabled: idleEnabled,
            activity: existing.activity,
            counters: existing.counters,
            bgmOwner: existing.bgmOwner,
            lastError: existing.lastError
        )
        runtimeStates[index] = ServerCountersRuntimeState(
            creatureId: creatureId,
            runtime: updatedRuntime
        )
    }

    public func updateRuntimeActivity(creatureId: String, activity: CreatureRuntimeActivity) {
        guard let index = runtimeStates.firstIndex(where: { $0.creatureId == creatureId }) else {
            return
        }
        guard let existing = runtimeStates[index].runtime else { return }
        let updatedRuntime = CreatureRuntime(
            idleEnabled: existing.idleEnabled,
            activity: activity,
            counters: existing.counters,
            bgmOwner: existing.bgmOwner,
            lastError: existing.lastError
        )
        runtimeStates[index] = ServerCountersRuntimeState(
            creatureId: creatureId,
            runtime: updatedRuntime
        )
    }

}

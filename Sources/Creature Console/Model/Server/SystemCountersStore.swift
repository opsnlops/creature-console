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

}

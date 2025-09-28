import Common
import SwiftUI

/// Wrapper around the SystemCountersDTO to allow for it to be observed and updated properly
@MainActor
public class SystemCountersStore: ObservableObject {
    public static let shared = SystemCountersStore()

    @Published public var systemCounters: SystemCountersDTO

    private init(systemCounters: SystemCountersDTO = SystemCountersDTO()) {
        self.systemCounters = systemCounters
    }

#if DEBUG
    /// Create an independent store instance for tests without touching the shared singleton.
    public static func makeForTesting(initial: SystemCountersDTO = SystemCountersDTO()) -> SystemCountersStore {
        return SystemCountersStore(systemCounters: initial)
    }
#endif

    // Update all of the counters at once
    public func update(with newCounters: SystemCountersDTO) {
        self.systemCounters = newCounters
    }

}

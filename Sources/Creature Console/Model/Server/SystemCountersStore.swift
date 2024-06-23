import Common
import SwiftUI

/// Wrapper around the SystemCountersDTO to allow for it to be observed and updated properly
public class SystemCountersStore: ObservableObject {
    public static let shared = SystemCountersStore()

    @Published public var systemCounters: SystemCountersDTO

    private init(systemCounters: SystemCountersDTO = SystemCountersDTO()) {
        self.systemCounters = systemCounters
    }


    // Update all of the counters at once
    public func update(with newCounters: SystemCountersDTO) {
        DispatchQueue.main.async {
            self.systemCounters = newCounters
        }
    }


}

import Common
import Foundation
import SwiftUI

struct SystemCountersItemProcessor {

    public static func processSystemCounters(_ counters: ServerCountersPayload) {
        Task { @MainActor in
            SystemCountersStore.shared.update(with: counters)
        }
    }
}

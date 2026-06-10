import Common
import Foundation
import SwiftUI

struct SystemCountersItemProcessor {

    public static func processSystemCounters(_ counters: ServerCountersPayload) async {
        await MainActor.run {
            SystemCountersStore.shared.update(with: counters)
        }
    }
}

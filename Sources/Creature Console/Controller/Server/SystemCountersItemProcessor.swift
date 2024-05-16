import Common
import Foundation
import SwiftUI


struct SystemCountersItemProcessor {

    public static func processSystemCounters(_ counters: SystemCountersDTO) {
        SystemCountersStore.shared.update(with: counters)
    }
}

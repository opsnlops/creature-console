import Common
import Foundation
import SwiftUI

struct EmergencyStopMessageProcessor {

    public static func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        Task {
            await AppState.shared.setSystemAlert(show: true, message: emergencyStop.reason)
        }
    }
}

import Common
import Foundation
import SwiftUI

struct EmergencyStopMessageProcessor {

    public static func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        AppState.shared.systemAlertMessage = emergencyStop.reason
        AppState.shared.showSystemAlert = true
    }
}

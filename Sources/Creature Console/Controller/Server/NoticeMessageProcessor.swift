import Common
import Foundation
import SwiftUI


struct NoticeMessageProcessor {

    public static func processNotice(_ notice: Notice) {
        AppState.shared.systemAlertMessage = notice.message
        AppState.shared.showSystemAlert = true
    }
}


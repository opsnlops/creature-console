import Common
import Foundation
import SwiftUI

struct NoticeMessageProcessor {

    public static func processNotice(_ notice: Notice) {
        let message = notice.message
        Task {
            await AppState.shared.setSystemAlert(show: true, message: message)
        }
    }
}

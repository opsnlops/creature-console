import Common
import Foundation
import SwiftUI

struct NoticeMessageProcessor {

    public static func processNotice(_ notice: Notice) async {
        await AppState.shared.setSystemAlert(show: true, message: notice.message)
    }
}

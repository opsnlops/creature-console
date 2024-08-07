import Common
import Foundation
import SwiftUI

#if os(macOS)
    struct LogViewScene: Scene {

        var body: some Scene {
            Window("Server Logs", id: "serverLogs") {
                LogView()
            }
            .defaultPosition(.topTrailing)
            .defaultSize(width: 500, height: 300)
            .keyboardShortcut("L", modifiers: [.command])
        }
    }
#endif

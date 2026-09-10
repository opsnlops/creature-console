import CreatureAppSupport
import SwiftUI

@main
struct BeakyCommunicatorApp: App {
    var body: some Scene {
        WindowGroup {
            ConversationRootView()
        }
        #if os(macOS)
            .defaultSize(width: 760, height: 720)
        #endif
    }
}

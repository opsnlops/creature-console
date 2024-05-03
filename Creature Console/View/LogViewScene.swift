
import Foundation
import SwiftUI

#if os(macOS)
struct LogViewScene: Scene {
       
    let server : CreatureServerClient
    
    init(server: CreatureServerClient) {
        self.server = server
    }
    
    
    var body: some Scene {
        Window("Server Logs", id: "serverLogs") {
            LogViewView(server: server)
        }
        .defaultPosition(.topTrailing)
        .defaultSize(width: 500, height: 300)
        .keyboardShortcut("L", modifiers: [.command])
    }
}
#endif

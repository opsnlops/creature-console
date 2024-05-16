import Common

/// Provide a way to (least attempt to) close the websocket cleanly when we shut down

#if os(iOS)
    import UIKit

    class ConsoleAppDelegate: NSObject, UIApplicationDelegate {
        let server = CreatureServerClient.shared

        func applicationWillTerminate(_ notification: Notification) {
            // We don't care about the returns, just close
            _ = server.disconnectWebsocket()
            server.close()
        }
    }
#endif


#if os(macOS)
    import Cocoa

    class ConsoleAppDelegate: NSObject, NSApplicationDelegate {
        let server = CreatureServerClient.shared

        func applicationWillTerminate(_ notification: Notification) {
            // We don't care about the returns, just close
            _ = server.disconnectWebsocket()
            server.close()
            print("Bye! 🖖🏻")
        }
    }
#endif

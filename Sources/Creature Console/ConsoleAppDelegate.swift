import Common

/// Provide a way to (least attempt to) close the websocket cleanly when we shut down

#if os(iOS)
    import UIKit

    class ConsoleAppDelegate: NSObject, UIApplicationDelegate {
        let server = CreatureServerClient.shared

        func applicationWillTerminate(_ notification: Notification) {
            // We don't care about the returns, just close
            Task {
                _ = await server.disconnectWebsocket()
            }
            server.close()
        }
    }
#endif


#if os(macOS)
    import Cocoa

    class ConsoleAppDelegate: NSObject, NSApplicationDelegate {
        let server = CreatureServerClient.shared

        func applicationDidFinishLaunching(_ notification: Notification) {
            // Enable AVPlayer logging for debugging
            setenv("AVPlayerLogLevelKey", "4", 1)

            // Continue with your setup code if needed
            print("App launched, AVPlayer logging enabled.")
        }

        func applicationWillTerminate(_ notification: Notification) {
            // We don't care about the returns, just close
            Task {
                _ = await server.disconnectWebsocket()
            }
            server.close()
            print("Bye! 🖖🏻")
        }
    }
#endif

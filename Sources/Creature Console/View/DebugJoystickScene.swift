import Common
import SwiftUI

#if os(macOS)
    struct DebugJoystickScene: Scene {

        var body: some Scene {
            Window("Debug Joystick", id: "debugJoystick") {
                JoystickDebugView()
            }
            .defaultPosition(.bottomTrailing)
            .defaultSize(width: 400, height: 150)
            .keyboardShortcut("J", modifiers: [.command])
        }
    }
#endif

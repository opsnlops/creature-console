import Common
import SwiftUI

#if os(macOS)
    struct ACWDebugJoystickScene: Scene {
        @ObservedObject var joystick: AprilsCreatureWorkshopJoystick

        init(joystick: AprilsCreatureWorkshopJoystick) {
            self.joystick = joystick
        }

        var body: some Scene {
            Window("Debug ACW Joystick", id: "debugACWJoystick") {
                JoystickDebugView()
            }
            .defaultPosition(.bottomTrailing)
            .defaultSize(width: 400, height: 150)
            .keyboardShortcut("K", modifiers: [.command])
        }
    }
#endif

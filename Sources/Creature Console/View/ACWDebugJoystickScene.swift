
import SwiftUI
import Common

#if os(macOS)
struct ACWDebugJoystickScene: Scene {
    @ObservedObject var joystick : AprilsCreatureWorkshopJoystick
    
    init(joystick: AprilsCreatureWorkshopJoystick)
    {
        self.joystick = joystick
    }
    
    var body: some Scene {
        Window("Debug ACW Joystick", id: "debugACWJoystick") {
            ACWJoystickDebugView(joystick: joystick)
        }
        .defaultPosition(.bottomTrailing)
        .defaultSize(width: 400, height: 150)
        .keyboardShortcut("K", modifiers: [.command])
    }
}
#endif


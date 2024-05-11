
import SwiftUI
import Common

#if os(macOS)
struct DebugJoystickScene: Scene {
    @ObservedObject var joystick : SixAxisJoystick
    
    init(joystick: SixAxisJoystick)
    {
        self.joystick = joystick
    }
    
    var body: some Scene {
        Window("Debug Joystick", id: "debugJoystick") {
            JoystickDebugView(joystick: joystick)
        }
        .defaultPosition(.bottomTrailing)
        .defaultSize(width: 400, height: 150)
        .keyboardShortcut("J", modifiers: [.command])
    }
}
#endif

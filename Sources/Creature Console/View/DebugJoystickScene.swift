//
//  DebugJoystickScene.swift
//  Creature Console
//
//  Created by April White on 4/9/23.
//

import SwiftUI

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

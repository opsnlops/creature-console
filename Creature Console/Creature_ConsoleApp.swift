//
//  Creature_ConsoleApp.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import SwiftUI
import Logging

@main
struct Creature_ConsoleApp: App {
    
    var eventLoop : EventLoop
    var audioManager = AudioManager()

    init() {
        let logger = Logger(label: "Creature Console")
        
        // Set up the configuration default
        let defaultPreferences: [String: Any] = [
            "serverAddress": "10.3.2.11",
            "serverPort": 6666,
            "serverLogsScrollBackLines": 50,
            "joystick0.leftThumbstick.xAxis.mapping": 0,
            "joystick0.leftThumbstick.yAxis.mapping": 1,
            "joystick0.rightThumbstick.xAxis.mapping": 2,
            "joystick0.rightThumbstick.yAxis.mapping": 3,
            "joystick0.leftTrigger.mapping": 4,
            "joystick0.rightTrigger.mapping": 5,
            "eventLoopMillisecondsPerFrame": 20,
            "logSpareTimeFrameInterval": 200,
            "audioVolume": 0.8
        ]
        UserDefaults.standard.register(defaults: defaultPreferences)
        
        self.eventLoop = EventLoop()
        
        // Init the joystick
        registerJoystickHandlers(eventLoop: self.eventLoop)
        
        // Connect to the server
        do {
            try CreatureServerClient.shared.connect(serverHostname: UserDefaults.standard.string(forKey: "serverAddress") ?? "127.0.0.1",
                                                    serverPort: UserDefaults.standard.integer(forKey: "serverPort"))
            logger.info("connected to server")
        } catch {
            print("Error opening connections: \(error)")
        }
    
    }
    
    var body: some Scene {
        WindowGroup {
            TopContentView()
                .environmentObject(CreatureServerClient.shared)
                .environmentObject(eventLoop)
                .environmentObject(audioManager)
        }
        
#if os(macOS)
        DebugJoystickScene(joystick: eventLoop.joystick0)
        LogViewScene(server: CreatureServerClient.shared)
        Settings {
            SettingsView()
        }
#endif
    
    }
}

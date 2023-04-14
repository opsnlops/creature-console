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
    
    @ObservedObject var joystick0 = SixAxisJoystick()

    init() {
        let logger = Logger(label: "Creature_ConsoleApp")
        
        setupController(joystick: joystick0)
        
        do {
            try CreatureServerClient.shared.connect(serverHostname: "10.3.2.11", serverPort: 6666)
            logger.info("connected to server")
        } catch {
            print("Error opening connections: \(error)")
        }
    
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(CreatureServerClient.shared)
                .environmentObject(joystick0)
        }
    
    }
}

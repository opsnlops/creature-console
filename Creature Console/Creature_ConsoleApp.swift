//
//  Creature_ConsoleApp.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import SwiftUI

@main
struct Creature_ConsoleApp: App {
    
    init() {
            do {
                try CreatureServerClient.shared.connect(serverHostname: "10.3.2.11", serverPort: 6666)
            } catch {
                print("Error opening connections: \(error)")
            }
        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(CreatureServerClient.shared)
        }
    }
}

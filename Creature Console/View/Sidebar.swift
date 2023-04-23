//
//  Sidebar.swift
//  Creature Console
//
//  Created by April White on 4/8/23.
//

import Foundation
import SwiftUI
import Logging


struct Sidebar: View {
    @StateObject var creatureList = CreatureList()
    @EnvironmentObject var client: CreatureServerClient
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    @EnvironmentObject var eventLoop : EventLoop
    

    
    let logger = Logger(label: "Sidebar")
        
    var body: some View {
        List {
            Section("Creatures") {
                if !creatureList.empty {
                    ForEach(creatureList.creatures, id: \.id) {
                        creature in
                        NavigationLink(creature.name, value: creature.id)
                            .navigationDestination(for: Data.self) {
                                CreatureDetail(creature: creatureList.getById(id: $0))
                            }
                    }
                    .navigationTitle("Creatures")
                }
                else {
                    Text("Trying to talk to \(UserDefaults.standard.string(forKey: "serverAddress") ?? "an undefined server")...")
                    ProgressView("Loading...")
                }
            }
            Section("Controls") {
                NavigationLink("Debug Joystick") {
                    JoystickDebugView(joystick: eventLoop.joystick0)
                }
                NavigationLink("Server Logs") {
                    LogViewView(server: client)
                }
                NavigationLink("Settings") {
                    SettingsView()
                }
                NavigationLink("Record Animation") {
                    RecordAnimation(joystick: eventLoop.joystick0)
                }
                NavigationLink("View Animation") {
                    ViewAnimation()
                }
            }
            .navigationTitle("April's Creature Workshop")
            
        }.onAppear {
            Task {
                
                if !creatureList.empty {
                    logger.debug("creature list exists, not re-loading")
                    return
                }
            
                logger.info("Attempting to load the creatures from  \(client.getHostname())")
                do {
                    let list : [Server_Creature]? = try await client.getAllCreatures()
                
                    // If we got somethign back, update the view
                    if let s = list {
                        for c in s {
                            creatureList.add(item: Creature(serverCreature: c))
                        }
                    }
                }
                catch {
                    logger.critical("\(error.localizedDescription)")
                    showErrorAlert = true
                    errorMessage = error.localizedDescription
                }
            }
            
        }.alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Oooooh Shit"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Fuck"))
            )
        }
        
    }
}


struct Sidebar_Previews: PreviewProvider {
    static var previews: some View {
        Sidebar()
    }
}

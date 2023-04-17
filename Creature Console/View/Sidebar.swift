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
        Group {
            if !creatureList.empty {
                VStack {
                    List(creatureList.creatures, id: \.id) {
                        creature in
                        NavigationLink(creature.name, value: creature.id)
                    }
                    .navigationDestination(for: Data.self) {
                        CreatureDetail(creature: creatureList.getById(id: $0))
                    }
                    .navigationTitle("Creatures")
                 
                    Spacer()
                    
                    #if !os(macOS)
                    List {
                        NavigationLink("Debug Joystick") {
                            JoystickDebugView(joystick: eventLoop.joystick0)
                        }
                        NavigationLink("Server Logs") {
                            LogViewView(server: client)
                        }
                        NavigationLink("Settings") {
                            SettingsView()
                        }
                    }
                    .navigationTitle("System")
                    #endif
                }
            }
            else {
                ProgressView("Loading...")
            }
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

//
//  ContentView.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import SwiftUI
import Logging


struct TopContentView: View {
    
    @EnvironmentObject var appState : AppState
    @EnvironmentObject var client : CreatureServerClient
    @EnvironmentObject var eventLoop : EventLoop
    
    @StateObject var creatureList = CreatureList()
    @State var animationIds = Set<AnimationIdentifier>()
    
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    @State var navigationPath = NavigationPath()

    @State private var selectedCreature: Creature?
 
    
    let logger = Logger(label: "Top Content View")

        
    var body: some View {
        
        NavigationSplitView {
            List {
                Section("Creatures") {
                    if !creatureList.empty {
                        ForEach(creatureList.creatures, id: \.id) {
                            creature in
                            NavigationLink(creature.name, value: creature.id)
                        }
                    }
                    else {
                        Text("Trying to talk to \(UserDefaults.standard.string(forKey: "serverAddress") ?? "an undefined server")...")
                        ProgressView("Loading...")
                            .padding()
                    }
                }
                
                
                Section("Controls") {
                    NavigationLink {
                        JoystickDebugView(joystick: eventLoop.joystick0)
                    } label: {
                        Label("Debug Joystick", systemImage: "gamecontroller")
                    }
                    NavigationLink {
                        LogViewView(server: client)
                    } label: {
                        Label("Server Logs", systemImage: "server.rack")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    NavigationLink {
                        AudioFilePicker()
                    } label: {
                        Label("Audio", systemImage: "music.note.list")
                    }
                }
            }
            .navigationTitle("Creature Console")
            .navigationDestination(for: Data.self) { creature in
                CreatureDetail(creature: creatureList.getById(id: creature))
            }
            .toolbar {
                ToolbarItem(id: "editCreature", placement: .primaryAction) {
                    NavigationLink(destination: EmptyView(), label: {
                        Image(systemName: "pencil")
                    })
                }
            }
            .onAppear {
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
        } detail: {
            NavigationStack(path: $navigationPath) {
                Text("Please choose a thing!")
                  .padding()
                }
           
        }
    }
}

struct TopContentView_Previews: PreviewProvider {
    static var previews: some View {
        TopContentView()
            .environmentObject(EventLoop.mock())
            .environmentObject(CreatureServerClient.mock())
    }
}


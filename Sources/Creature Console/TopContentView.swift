

import SwiftUI
import OSLog


struct TopContentView: View {
    
    let appState = AppState.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared

    // TODO: Is a StateObject actually what I want here?
    @StateObject var creatureCache = CreatureCache()

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    @State var navigationPath = NavigationPath()

    @State private var selectedCreature: Creature?
 
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TopContentView")

        
    var body: some View {
        
        NavigationSplitView {
            List {
                Section("Creatures") {
                    if !creatureCache.empty {
                        ForEach(creatureCache.creatures, id: \.id) {
                            creature in
                            NavigationLink(creature.name, value: creature.id)
                        }
                    }
                    else {
                        Text("Trying to talk to \(server.getHostname())...")
                            .padding()
                    }
                }
                
                
                Section("Controls") {
                    NavigationLink {
                        JoystickDebugView(joystick: eventLoop.sixAxisJoystick)
                    } label: {
                        Label("Debug Joystick", systemImage: "gamecontroller")
                    }
                    //NavigationLink {
                    //    LogViewView(server: client)
                    //} label: {
                    //    Label("Server Logs", systemImage: "server.rack")
                    //}
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
            .navigationDestination(for: CreatureIdentifier.self) { creature in
                CreatureDetail(creature: creatureCache.getById(id: creature))
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
                    
                    if !creatureCache.empty {
                        logger.debug("creature list exists, not re-loading")
                        return
                    }
                
                    logger.info("Attempting to load the creatures from \(server.getHostname())")

                    let result = await server.getAllCreatures()
                    switch result {
                    case .success(let creatures):
                       for creature in creatures {
                           creatureCache.add(item: creature)
                       }
                    case .failure(let error):
                       let errorMessage = error.localizedDescription
                       logger.critical("\(errorMessage)")
                       showErrorAlert = true
                       self.errorMessage = errorMessage
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


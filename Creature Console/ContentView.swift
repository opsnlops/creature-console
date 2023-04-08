//
//  ContentView.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import SwiftUI
import Logging




struct ContentView: View {
    @EnvironmentObject var client: CreatureServerClient
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @ObservedObject private var creature: Creature
    
    let logger = Logger(label: "ContentView")
    
    init() {
        setupController()
        creature = .mock()
    }
    
    var body: some View {
        
        NavigationSplitView {
            Text("Hello")
        } detail: {
            
            VStack {
                
                CreatureDetail(creature: creature)
                Button("Do it!") {
                    Task {
                        
                        logger.debug("Trying to talk to  \(client.getHostname())")
                        do {
                            let serverCreature : Server_Creature? = try await client.searchCreatures(creatureName: "Beaky1")
                            
                            // If we got somethign back, update the view
                            if let s = serverCreature {
                                creature.updateFromServerCreature(serverCreature: s)
                            }
                            
                        }
                        catch {
                            logger.critical("\( error.localizedDescription)")
                            showErrorAlert = true
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .alert(isPresented: $showErrorAlert) {
                    Alert(
                        title: Text("Oooooh Shit"),
                        message: Text(errorMessage),
                        dismissButton: .default(Text("Fuck"))
                    )
                }
            }
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

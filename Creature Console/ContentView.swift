//
//  ContentView.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import SwiftUI
import Logging



struct DetailView : View {
    
    var body: some View {
        VStack {
            Text("Details")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    print("Adding Book")
                }, label: {
                    Label("Add Book", systemImage: "plus")
                })
            }
        }
        .navigationTitle("My Title")
        #if os(macOS)
        .navigationSubtitle("My Subtitle")
        #endif
    }
    
}

struct MenuView : View {
    
    var body: some View {
        VStack {
            Text("Menu")
        }
    }
    
}




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
        VStack {
            
    
            CreatureDetail(creature: creature)
            Button("Do it!") {
                Task {
                
                    logger.debug("Trying to talk to  \(client.getHostname())")
                    do {
                        let serverCreature : Server_Creature? = try await client.getCreature(creatureName: "Beaky3")
                        
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

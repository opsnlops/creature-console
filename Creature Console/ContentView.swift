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
    
    let logger = Logger(label: "ContentView")
    
    
    var body: some View {
        VStack {
            Button("Do it!") {
                Task {
                
                    logger.debug("Trying to talk to  \(client.getHostname())")
                    do {
                        let creature = try await client.getCreature(creatureName: "Beaky3")
                        print("number of motors: \(creature.numberOfMotors)")
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

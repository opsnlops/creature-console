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
    
    init() {
        setupController()
    }
    
    var body: some View {
        
        NavigationSplitView {
            Sidebar()
        } detail: {
           Text("Please select a creature!")
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


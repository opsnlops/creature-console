//
//  ContentView.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import SwiftUI
import Logging


struct ContentView: View {
    @ObservedObject var joystick0 : SixAxisJoystick
    
    let logger = Logger(label: "ContentView")
    
    init() {
        self.joystick0 = SixAxisJoystick()
        setupController(joystick: joystick0)
    }
    
    var body: some View {
        
        NavigationSplitView {
            Sidebar()
        } detail: {
           //Text("Please select a creature!")
           // .padding()
            JoystickDebugView(joystick: joystick0)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


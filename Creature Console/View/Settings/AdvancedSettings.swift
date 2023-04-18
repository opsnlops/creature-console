//
//  AdvancedSettings.swift
//  Creature Console
//
//  Created by April White on 4/17/23.
//

import Foundation
import SwiftUI



struct AdvancedSettingsView: View {
    @AppStorage("eventLoopFramesPerSecond") private var eventLoopFramesPerSecond: Double = 40.0
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Event Loop FPS (Restart Required)")) {
                    TextField("", value: $eventLoopFramesPerSecond, format: .number)
                }
            }
            Spacer()
        }
    }
}

struct AdvancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettingsView()
    }
}

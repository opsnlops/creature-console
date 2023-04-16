//
//  SettingsView.swift
//  Creature Console
//
//  Created by April White on 4/14/23.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, advanced
    }
    var body: some View {
        TabView {
            NetworkSettingsView()
                .tabItem {
                    Label("Network", systemImage: "network")
                }
                .tag(Tabs.general)
            JoystickSettingsView()
                .tabItem {
                    Label("Joystick", systemImage: "gamecontroller.fill")
                }
                .tag(Tabs.advanced)
            UISettingsView()
                .tabItem {
                    Label("Interface", systemImage: "paintpalette.fill")
                }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 600, height: 400)
        #endif
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

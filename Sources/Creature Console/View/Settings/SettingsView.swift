import Common
import Foundation
import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case network, joystick, interface, advanced, grossHacks
    }
    var body: some View {
        TabView {
            NetworkSettingsView()
                .tabItem {
                    Label("Network", systemImage: "network")
                }
                .tag(Tabs.network)
            JoystickSettingsView()
                .tabItem {
                    Label("Joystick", systemImage: "gamecontroller")
                }
                .tag(Tabs.joystick)
            InterfaceSettings()
                .tabItem {
                    Label("Interface", systemImage: "paintpalette")
                }
                .tag(Tabs.interface)
            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "wand.and.stars")
                }
                .tag(Tabs.advanced)
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

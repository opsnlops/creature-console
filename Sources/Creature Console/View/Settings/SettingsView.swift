import Common
import Foundation
import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case network, joystick, interface, advanced, debug
    }
    var body: some View {
        ZStack {
            // Liquid Glass background behind the entire settings container
            LiquidGlass()
                .ignoresSafeArea()

            #if os(tvOS)
                NetworkSettingsView()
            #else
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
                    DebugSettingsView()
                        .tabItem {
                            Label("Debug", systemImage: "ladybug")
                        }
                        .tag(Tabs.debug)
                }
            #endif
        }
        #if os(macOS)
            .frame(width: 760, height: 520)
        #endif
    }
}

#Preview {
    SettingsView()
}

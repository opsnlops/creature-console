import AppKit
import SwiftUI

@main
struct LightweightConsoleApp: App {
    private let controller: LightweightClientController
    @StateObject private var viewModel: LightweightClientViewModel

    init() {
        let controller = LightweightClientController()
        self.controller = controller
        _viewModel = StateObject(
            wrappedValue: LightweightClientViewModel(controller: controller)
        )
    }

    var body: some Scene {
        MenuBarExtra("Creature Control", systemImage: "pawprint.fill") {
            MenuBarContentView(
                viewModel: viewModel,
                openPreferences: showPreferences,
                quitApp: terminateApp
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(controller: controller, viewModel: viewModel)
        }
    }

    private func showPreferences() {
        let showSettingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.responds(to: showSettingsSelector)
            && NSApp.sendAction(showSettingsSelector, to: nil, from: nil)
        {
            return
        }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    private func terminateApp() {
        NSApp.terminate(nil)
    }
}

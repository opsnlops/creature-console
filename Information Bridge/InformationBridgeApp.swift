import AppKit
import SwiftUI

/// The Information Bridge: what April's Mac knows, the world learns. A source of facts for
/// Beaky - never a bird. It reads private things here, on this Mac, and sends only distilled facts
/// to Creature World through a durable outbox. Plan: `docs/information-bridge-plan.md`.
@main
struct InformationBridgeApp: App {
    @State private var store = BridgeStore()
    /// Held for the life of the app: macOS must never nap it. The first night showed the
    /// five-minute heartbeat arriving every ten - App Nap stretching a menu-bar app's timers
    /// once its window is closed - and this also asks the system not to idle-sleep.
    @State private var wakefulness = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled],
        reason: "Reading the house for the birds, all the time")

    init() {
        // One Bridge per Mac: launchd relaunching beside a copy run from Xcode, or a second
        // click on the icon, must not make two. The newcomer leaves.
        if !BridgeStore.isHostingTests,
            NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
            ).count > 1
        {
            NSApplication.shared.terminate(nil)
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            BridgeRootView(store: store)
        }
        .defaultSize(width: 900, height: 620)

        // April's map from address-book cards to the world's people.
        Window("People", id: "people") {
            PeopleView(store: store)
        }
        .defaultSize(width: 760, height: 520)

        // The numbers whose texts are read without a card: carriers, and whoever April allows.
        Window("Senders", id: "senders") {
            SendersView(store: store)
        }
        .defaultSize(width: 640, height: 520)

        // The Bridge keeps working with the window closed; the menu bar is where it shows.
        MenuBarExtra {
            BridgeMenu(store: store)
        } label: {
            Image(systemName: store.menuBarSymbol)
        }

        Settings {
            BridgeSettingsView()
                .frame(width: 540, height: 460)
        }
    }
}

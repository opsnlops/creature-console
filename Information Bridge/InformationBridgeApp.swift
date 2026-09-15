import SwiftUI

/// The Information Bridge: what April's Mac knows, the world learns. A source of facts for
/// Beaky - never a bird. It reads private things here, on this Mac, and sends only distilled facts
/// to Creature World through a durable outbox. Plan: `docs/information-bridge-plan.md`.
@main
struct InformationBridgeApp: App {
    @State private var store = BridgeStore()

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

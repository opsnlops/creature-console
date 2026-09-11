import SwiftUI

@main
struct WorldViewerApp: App {
    @State private var store = WorldStore()

    var body: some Scene {
        WindowGroup {
            WorldViewerRootView(store: store)
        }
        .defaultSize(width: 1_180, height: 760)

        Settings {
            WorldViewerSettingsView()
                .frame(width: 540, height: 520)
        }
    }
}

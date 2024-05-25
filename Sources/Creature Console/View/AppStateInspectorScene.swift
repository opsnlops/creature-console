
import SwiftUI
import Common

#if os(macOS)
struct AppStateInspectorScene: Scene {

    var body: some Scene {
        Window("AppState Inspector", id: "appStateInspector") {
            AppStateInspectorView()
        }
        .defaultPosition(.bottomTrailing)
        .defaultSize(width: 400, height: 150)
        .keyboardShortcut(".", modifiers: [.command])
    }
}
#endif


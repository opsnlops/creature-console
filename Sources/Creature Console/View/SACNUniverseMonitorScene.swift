import SwiftUI

#if os(macOS) || os(iOS)
    struct SACNUniverseMonitorScene: Scene {
        var body: some Scene {
            #if os(macOS)
                Window("sACN Universe Monitor", id: "sacnUniverseMonitor") {
                    SACNUniverseMonitorView()
                }
                .defaultSize(width: 980, height: 640)
            #else
                WindowGroup(id: "sacnUniverseMonitor") {
                    SACNUniverseMonitorView()
                }
            #endif
        }
    }
#endif

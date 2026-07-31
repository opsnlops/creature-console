#if os(macOS)
    import SwiftUI

    struct SpatialStageScene: Scene {
        var body: some Scene {
            Window("Spatial Stage", id: "spatialStage") {
                SpatialStageView()
            }
            .defaultSize(width: 1_180, height: 760)
        }
    }

    struct SpatialStageCommands: Commands {
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandMenu("Audio") {
                Button("Open Spatial Stage") {
                    openWindow(id: "spatialStage")
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
    }
#endif

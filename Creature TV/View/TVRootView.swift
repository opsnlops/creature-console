import Common
import SwiftData
import SwiftUI

/// The TV's navigation root: a native tvOS `TabView` with the floating sidebar
/// (`.sidebarAdaptable`), one `NavigationStack` per tab.
///
/// This replaced a shared `NavigationSplitView` that focus-trapped on tvOS — pushed
/// full-screen views (the sACN monitor especially) had no rail back to the sidebar. With a
/// stack per tab, Menu always pops toward the tab root, and at the root it surfaces the tab
/// bar: dead ends are structurally impossible (#72).
struct TVRootView: View {

    @State private var hideStatusToolbar = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                Tab("Creatures", systemImage: "pawprint.circle") {
                    NavigationStack { TVCreaturesView() }
                }
                Tab("Live Magic", systemImage: "sparkles.rectangle.stack") {
                    NavigationStack { LiveMagicView() }
                }
                Tab("Animations", systemImage: "figure.socialdance") {
                    NavigationStack { TVAnimationTriggerView() }
                }
                Tab("Soundboard", systemImage: "speaker.wave.2") {
                    NavigationStack { TVSoundboardView() }
                }
                Tab("Spatial Audition", systemImage: "person.wave.2") {
                    NavigationStack { TVSpatialAuditionView() }
                }
                Tab("Live Monitor", systemImage: "antenna.radiowaves.left.and.right") {
                    NavigationStack { TVLiveStageView() }
                }
                Tab("Diagnostics", systemImage: "stethoscope") {
                    NavigationStack { TVDiagnosticsView() }
                }
                Tab("Settings", systemImage: "gear") {
                    NavigationStack { SettingsView() }
                }
            }
            .tabViewStyle(.sidebarAdaptable)

            if !hideStatusToolbar {
                BottomToolBarView()
            }
        }
        .onPreferenceChange(HideBottomToolbarPreferenceKey.self) { hide in
            hideStatusToolbar = hide
        }
    }
}

/// The Creatures tab: pick a bird, see its health and sensors. Backed by the SwiftData
/// mirror, which the bootstrapper seeds and cache invalidations keep fresh.
struct TVCreaturesView: View {

    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    var body: some View {
        Group {
            if creatures.isEmpty {
                ContentUnavailableView {
                    Label("No Creatures", systemImage: "pawprint.circle")
                } description: {
                    Text("Creatures sync from the server automatically once it's reachable.")
                }
            } else {
                List(creatures) { creature in
                    NavigationLink {
                        CreatureDetail(creature: creature.toDTO())
                    } label: {
                        Label(creature.name, systemImage: "pawprint.circle")
                    }
                }
            }
        }
        .navigationTitle("Creatures")
    }
}

/// The Diagnostics tab: the deep-inspection screens, each a push so Menu walks back out.
struct TVDiagnosticsView: View {

    var body: some View {
        List {
            NavigationLink {
                TVSACNUniverseMonitorView()
            } label: {
                Label("sACN Universe Monitor", systemImage: "dot.radiowaves.left.and.right")
                    .symbolRenderingMode(.hierarchical)
            }

            NavigationLink {
                JoystickDebugView()
            } label: {
                Label("Debug Joystick", systemImage: "gamecontroller")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .navigationTitle("Diagnostics")
    }
}

import Common
import Foundation
import SwiftData
import SwiftUI

struct AppStateInspectorView: View {

    @State private var appState = AppStateData(
        currentActivity: .idle,
        currentAnimation: nil,
        selectedTrack: nil,
        showSystemAlert: false,
        systemAlertMessage: ""
    )

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query private var creatures: [CreatureModel]
    @Query private var animations: [AnimationMetadataModel]

    var body: some View {

        VStack {

            Section("Activity") {
                Text(appState.currentActivity.description)
            }

            Section("Caches") {
                Text("Creature Cache: \(creatures.count)")
                Text("Animation Cache: \(animations.count)")
            }

            Spacer()
        }
        .task {
            // Subscribe to AppState updates
            for await state in await AppState.shared.stateUpdates {
                await MainActor.run {
                    appState = state
                }
            }
        }

    }
}


struct AppStateInspectorView_Previews: PreviewProvider {
    static var previews: some View {
        AppStateInspectorView()
    }
}

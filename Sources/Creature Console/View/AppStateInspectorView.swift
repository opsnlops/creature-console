import Common
import Foundation
import SwiftUI

struct AppStateInspectorView: View {

    @State private var appState = AppStateData(
        currentActivity: .idle,
        currentAnimation: nil,
        selectedTrack: nil,
        showSystemAlert: false,
        systemAlertMessage: ""
    )
    @State private var creatureCacheState = CreatureCacheState(creatures: [:], empty: true)
    @State private var animationCacheState = AnimationMetadataCacheState(
        metadatas: [:], empty: true)

    var body: some View {

        VStack {
            Section("Current Animation") {

                if let a = appState.currentAnimation {
                    Text("Title: \(a.metadata.title)")
                    Text("Millisecond Per Frame: \(a.metadata.millisecondsPerFrame)")
                    Text("Track count: \(a.tracks.count)")
                } else {
                    Text("Is nil")
                }

            }

            Section("Activity") {
                Text(appState.currentActivity.description)
            }

            Section("Caches") {
                Text("Creature Cache: \(creatureCacheState.creatures.count)")
                Text("Animation Cache: \(animationCacheState.metadatas.count)")
            }

            Spacer()
        }
        .task {
            // Subscribe to cache updates
            async let creatureTask: Void = {
                for await state in await CreatureCache.shared.stateUpdates {
                    await MainActor.run {
                        creatureCacheState = state
                    }
                }
            }()

            async let animationTask: Void = {
                for await state in await AnimationMetadataCache.shared.stateUpdates {
                    await MainActor.run {
                        animationCacheState = state
                    }
                }
            }()

            async let appStateTask: Void = {
                for await state in await AppState.shared.stateUpdates {
                    await MainActor.run {
                        appState = state
                    }
                }
            }()

            _ = await (creatureTask, animationTask, appStateTask)
        }

    }
}


struct AppStateInspectorView_Previews: PreviewProvider {
    static var previews: some View {
        AppStateInspectorView()
    }
}

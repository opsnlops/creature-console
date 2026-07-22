import Common
import Foundation
import SwiftData
import SwiftUI

struct AppStateInspectorView: View {

    @Environment(ConsoleStore.self) private var console

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query private var creatures: [CreatureModel]
    @Query private var animations: [AnimationMetadataModel]

    var body: some View {

        VStack {

            Section("Activity") {
                Text(console.currentActivity.description)
            }

            Section("Caches") {
                Text("Creature Cache: \(creatures.count)")
                Text("Animation Cache: \(animations.count)")
            }

            Spacer()
        }

    }
}


#Preview {
    AppStateInspectorView()
        .environment(ConsoleStore.shared)
}

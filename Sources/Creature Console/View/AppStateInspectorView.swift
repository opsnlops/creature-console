import Common
import Foundation
import SwiftUI




struct AppStateInspectorView: View {

    @ObservedObject var appState = AppState.shared

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

            Spacer()
        }

    }
}



struct AppStateInspectorView_Previews: PreviewProvider {
    static var previews: some View {
        AppStateInspectorView()
    }
}

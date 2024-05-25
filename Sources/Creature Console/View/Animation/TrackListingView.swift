import Common
import OSLog
import SwiftUI

struct TrackListingView: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TrackListingView")

    @ObservedObject var appState = AppState.shared
    @ObservedObject var creatureCache = CreatureCache.shared

    @State var showErrorMessage: Bool = false
    @State var errorMessage: String = ""

    var body: some View {
        ScrollView {
            VStack {
                if let currentAnimation = appState.currentAnimation {

                    if currentAnimation.tracks.isEmpty {
                        Text("No tracks")
                    } else {
                        ForEach(currentAnimation.tracks) { track in
                            prepareTrackView(for: track)
                        }
                    }


                } else {
                    Text("No animation loaded into the appState")
                }
            }
            .alert(isPresented: $showErrorMessage) {
                Alert(
                    title: Text("Error Viewing Track"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Shit"))
                )
            }
        }

    }


    func prepareTrackView(for track: Track) -> some View {

        logger.debug("preparing a track view!")

        switch creatureCache.getById(id: track.creatureId) {
        case .success(let creature):
            let inputs = creature.inputs
            return TrackViewer(
                track: track,
                creature: creature,
                inputs: inputs,
                chartColor: pickRandomColor())

        case .failure(let error):
            errorMessage = "Unable to locate creature in cache: \(error.localizedDescription)"
            showErrorMessage = true
            return TrackViewer(
                track: track,
                creature: .mock(),
                inputs: [])
        }

        func pickRandomColor() -> Color {
            let colors: [Color] = [
                .red, .green, .blue, .orange, .yellow, .pink, .purple, .teal, .accentColor,
            ]
            return colors.randomElement() ?? .accentColor
        }

    }


}


struct TrackListingView_Previews: PreviewProvider {

    var appState = AppState.shared
    var creatureCache = CreatureCache.shared

    static var previews: some View {
        TrackListingView()
    }
}

import Common
import OSLog
import SwiftUI

struct TrackListingView: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TrackListingView")

    @State private var appState = AppStateData(
        currentActivity: .idle, currentAnimation: nil, selectedTrack: nil, showSystemAlert: false,
        systemAlertMessage: "")
    @State private var creatureCacheState = CreatureCacheState(creatures: [:], empty: true)

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
            .task {
                async let appStateTask: Void = {
                    for await state in await AppState.shared.stateUpdates {
                        await MainActor.run {
                            appState = state
                        }
                    }
                }()

                async let creatureCacheTask: Void = {
                    for await state in await CreatureCache.shared.stateUpdates {
                        await MainActor.run {
                            creatureCacheState = state
                        }
                    }
                }()

                await appStateTask
                await creatureCacheTask
            }
        }

    }


    func prepareTrackView(for track: Track) -> some View {

        logger.debug("preparing a track view!")

        if let creature = creatureCacheState.creatures[track.creatureId] {
            let inputs = creature.inputs
            return TrackViewer(
                track: track,
                creature: creature,
                inputs: inputs,
                chartColor: pickRandomColor())
        } else {
            DispatchQueue.main.async {
                errorMessage = "Unable to locate creature in cache: \(track.creatureId)"
                showErrorMessage = true
            }
            return TrackViewer(
                track: track,
                creature: .mock(),
                inputs: [])
        }
    }

    func pickRandomColor() -> Color {
        let colors: [Color] = [
            .red, .green, .blue, .orange, .yellow, .pink, .purple, .teal, .accentColor,
        ]
        return colors.randomElement() ?? .accentColor
    }


}


struct TrackListingView_Previews: PreviewProvider {

    static var previews: some View {
        TrackListingView()
    }
}

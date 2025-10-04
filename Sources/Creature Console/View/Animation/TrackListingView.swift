import Common
import OSLog
import SwiftData
import SwiftUI

struct TrackListingView: View {
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TrackListingView")
    let animation: Common.Animation?

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query private var creatures: [CreatureModel]

    var body: some View {
        ScrollView {
            VStack {
                if let currentAnimation = animation {
                    if currentAnimation.tracks.isEmpty {
                        Text("No tracks")
                    } else {
                        ForEach(currentAnimation.tracks) { track in
                            prepareTrackView(for: track)
                        }
                    }
                } else {
                    Text("No animation loaded")
                }
            }
        }

    }


    func prepareTrackView(for track: Track) -> some View {
        logger.debug("preparing a track view!")

        if let creature = creatures.first(where: { $0.id == track.creatureId }) {
            let creatureDTO = creature.toDTO()
            let inputs = creatureDTO.inputs
            return AnyView(
                TrackViewer(
                    track: track,
                    creature: creatureDTO,
                    inputs: inputs,
                    chartColor: colorForTrack(track)
                )
            )
        } else {
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    Label("Missing creature for track", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text("Creature id \(track.creatureId) not found in cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            )
        }
    }

    func colorForTrack(_ track: Track) -> Color {
        let palette: [Color] = [
            .red, .green, .blue, .orange, .yellow, .pink, .purple, .teal, .accentColor,
        ]
        // Create a stable hash from the track id
        var hasher = Hasher()
        hasher.combine(track.id)
        let index = abs(hasher.finalize()) % palette.count
        return palette[index]
    }

}


struct TrackListingView_Previews: PreviewProvider {
    static var previews: some View {
        TrackListingView(animation: .mock())
    }
}

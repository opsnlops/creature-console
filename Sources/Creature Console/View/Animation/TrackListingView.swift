import Common
import OSLog
import SwiftData
import SwiftUI

struct TrackListingView: View {
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TrackListingView")
    let animation: Common.Animation?
    /// Dialog provenance for this animation's sound file, matched to each track by audio channel
    /// (name fallback). Nil for hand-made animations (tracks then render without the dialog section).
    var provenance: DialogProvenance? = nil

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query private var creatures: [CreatureModel]

    var body: some View {
        // Group the script by speaker once, not per-track — a per-creature filter would re-parse
        // the whole script on every track.
        let linesBySpeaker = provenance?.linesBySpeaker ?? [:]

        // No ScrollView here — this view is always embedded in the AnimationEditor's ScrollView, so
        // a nested one just fights the outer scroll (and prevented the last track from scrolling
        // clear of the bottom toolbar).
        return VStack {
            if let currentAnimation = animation {
                if currentAnimation.tracks.isEmpty {
                    Text("No tracks")
                } else {
                    ForEach(currentAnimation.tracks) { track in
                        prepareTrackView(for: track, linesBySpeaker: linesBySpeaker)
                    }
                }
            } else {
                Text("No animation loaded")
            }
        }
    }


    func prepareTrackView(
        for track: Track, linesBySpeaker: [String: [DialogProvenance.ScriptLine]]
    ) -> some View {
        logger.debug("preparing a track view!")

        if let creature = creatures.first(where: { $0.id == track.creatureId }) {
            let creatureDTO = creature.toDTO()
            let inputs = creatureDTO.inputs
            // Match this creature's dialog lane by audio channel (stable across renames), falling
            // back to name for legacy provenance without a matching channel. Script lines are then
            // attributed via the lane's *recorded* name, so a creature renamed after the render
            // still shows its ribbon and lines.
            let lipsync =
                provenance?.lipsync.first { $0.channel == creatureDTO.audioChannel }
                ?? provenance?.lipsync.first {
                    $0.name.caseInsensitiveCompare(creatureDTO.name) == .orderedSame
                }
            // Word-level alignment (#56) for this lane, matched the same way. Present only on
            // newer renders; nil ones fall back to showing the mouth shape at the cursor.
            let wordTrack =
                provenance?.words.first { $0.channel == creatureDTO.audioChannel }
                ?? provenance?.words.first {
                    $0.name.caseInsensitiveCompare(creatureDTO.name) == .orderedSame
                }
            let speakerName = lipsync?.name ?? creatureDTO.name
            let lines = linesBySpeaker[speakerName.lowercased()] ?? []
            return AnyView(
                TrackViewer(
                    track: track,
                    creature: creatureDTO,
                    inputs: inputs,
                    chartColor: colorForTrack(track),
                    lipsync: lipsync,
                    wordTrack: wordTrack,
                    scriptLines: lines,
                    millisecondsPerFrame: animation?.metadata.millisecondsPerFrame ?? 20
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

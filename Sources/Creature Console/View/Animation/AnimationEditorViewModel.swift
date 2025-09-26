import Common
import Foundation
import OSLog
import SwiftUI

@MainActor
final class AnimationEditorViewModel: ObservableObject {
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditorViewModel")

    @Published var animation: Common.Animation

    // Editable metadata fields mirrored for SwiftUI bindings
    @Published var title: String = ""
    @Published var soundFile: String = ""
    @Published var note: String = ""
    @Published var multitrackAudio: Bool = false
    @Published var millisecondsPerFrame: UInt32 = 20

    // Force TrackListingView rebuilds when tracks change
    @Published var tracksVersion: Int = 0

    init(animation: Common.Animation) {
        self.animation = animation
        syncFromAnimation()
    }

    func syncFromAnimation() {
        title = animation.metadata.title
        soundFile = animation.metadata.soundFile
        note = animation.metadata.note
        multitrackAudio = animation.metadata.multitrackAudio
        millisecondsPerFrame = animation.metadata.millisecondsPerFrame
        tracksVersion = Int(animation.tracks.count)
    }

    func updateMetadataFromFields() {
        animation.metadata.title = title
        animation.metadata.soundFile = soundFile
        animation.metadata.note = note
        animation.metadata.multitrackAudio = multitrackAudio
        animation.metadata.millisecondsPerFrame = millisecondsPerFrame
    }

    func appendTrack(_ track: Track) {
        animation.tracks.append(track)
        animation.recalculateNumberOfFrames()
        tracksVersion = Int(animation.tracks.count)
        logger.debug("Appended track; total tracks now: \(self.animation.tracks.count)")
    }
}

import Common
import Foundation
import OSLog
import SwiftUI

@MainActor
@Observable
final class AnimationEditorViewModel {
    @ObservationIgnored private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditorViewModel")

    var animation: Common.Animation

    // Editable metadata fields mirrored for SwiftUI bindings
    var title: String = ""
    var soundFile: String = ""
    var note: String = ""
    var multitrackAudio: Bool = false
    var millisecondsPerFrame: UInt32 = 20

    // Force TrackListingView rebuilds when tracks change
    var tracksVersion: Int = 0

    init(animation: Common.Animation) {
        self.animation = animation
        syncFromAnimation()
    }

    /// Replace the whole animation with a freshly-fetched copy (e.g. after an in-place
    /// dialog re-render, which overwrites the same `animation_id` server-side). Bumps
    /// `tracksVersion` so `TrackListingView` rebuilds even when the track count is unchanged.
    func reload(with animation: Common.Animation) {
        self.animation = animation
        syncFromAnimation()
        tracksVersion &+= 1
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

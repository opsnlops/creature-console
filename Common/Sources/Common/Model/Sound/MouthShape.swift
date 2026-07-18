import Foundation

/// The canonical mapping from a Rhubarb-style mouth shape letter to a servo openness value
/// (0 = closed, 255 = wide open). This is the single source of truth used both when importing
/// Rhubarb JSON into a mouth axis (`SoundData.MouthCue.intValue`) and when rendering a dialog
/// render's embedded mouth cues as an activity ribbon — so the ribbon reads identically to what
/// the mouth servo actually does.
///
/// `X` is the idle/rest shape (mouth fully closed, i.e. silence); everything else is some degree
/// of open. An unrecognized shape falls back to the near-closed `A` value.
public enum MouthShape {

    public static func openness(_ shape: String) -> UInt8 {
        switch shape {
        case "A": return 5
        case "B": return 180
        case "C": return 240
        case "D": return 255
        case "E": return 50
        case "F": return 20
        case "X": return 0
        default: return 5
        }
    }

    /// Whether this shape represents silence (the mouth at rest). Rhubarb emits contiguous cues
    /// covering the whole timeline, so "is this creature speaking right now" is "shape isn't rest".
    public static func isSilent(_ shape: String) -> Bool {
        openness(shape) == 0
    }

    /// Bake a sequence of timed mouth values into a per-frame openness byte array — the exact
    /// mapping the client used to apply when it generated mouth data locally (Rhubarb JSON →
    /// mouth axis). Extracted so both that import path and the dialog-provenance activity ribbon
    /// bake through the same code, and the ribbon renders byte-for-byte like a real mouth track.
    ///
    /// Each value paints frames `[start, end)` (in seconds, at `millisecondsPerFrame`) with its
    /// openness; frames no cue covers stay 0 (closed). Out-of-range frames are clamped.
    public static func bakeFrames(
        _ cues: [TimedMouthValue], millisecondsPerFrame: UInt32, frameCount: Int
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: max(0, frameCount))
        guard frameCount > 0, millisecondsPerFrame > 0 else { return bytes }

        for cue in cues {
            let startFrame = max(
                0, min(frameCount, Int((cue.start * 1000.0) / Double(millisecondsPerFrame))))
            let endFrame = max(
                startFrame,
                min(frameCount, Int((cue.end * 1000.0) / Double(millisecondsPerFrame))))
            if endFrame > startFrame {
                bytes.replaceSubrange(
                    startFrame..<endFrame,
                    with: repeatElement(cue.openness, count: endFrame - startFrame))
            }
        }
        return bytes
    }
}

/// A mouth openness (0…255) held over a `[start, end)` time span in seconds. The common currency
/// between Rhubarb cues (`SoundData.MouthCue`) and dialog-render cues (`DialogProvenance.MouthCue`)
/// so both can bake through `MouthShape.bakeFrames`.
public struct TimedMouthValue: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let openness: UInt8

    public init(start: Double, end: Double, openness: UInt8) {
        self.start = start
        self.end = end
        self.openness = openness
    }
}

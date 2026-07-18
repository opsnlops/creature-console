import Foundation

extension DialogProvenance {

    /// One parsed line of the rendered script: who speaks and what they say. Derived from the flat
    /// `Speaker: text` script text so the UI can attribute lines to a specific creature's track.
    public struct ScriptLine: Sendable, Equatable, Identifiable {
        /// Position in the full script (stable id, and the ordering across all speakers).
        public let index: Int
        public let speaker: String
        public let text: String
        public var id: Int { index }

        public init(index: Int, speaker: String, text: String) {
            self.index = index
            self.speaker = speaker
            self.text = text
        }
    }

    /// The full script parsed into `{speaker, text}` lines. A line is `Speaker: text`; we split on
    /// the **first** colon only, so colons inside the spoken text (e.g. "3:1") stay intact. Lines
    /// with no colon or an empty speaker are dropped (defensive — the server emits well-formed
    /// turns).
    public var parsedScriptLines: [ScriptLine] {
        scriptLines.enumerated().compactMap { index, raw in
            guard let colon = raw.firstIndex(of: ":") else { return nil }
            let speaker = raw[..<colon].trimmingCharacters(in: .whitespaces)
            let text = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !speaker.isEmpty else { return nil }
            return ScriptLine(index: index, speaker: speaker, text: text)
        }
    }

    /// The lines spoken by a given creature/channel name, in script order. Case-insensitive so
    /// "Beaky" matches "beaky".
    public func lines(forSpeaker name: String) -> [ScriptLine] {
        parsedScriptLines.filter { $0.speaker.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// All script lines grouped by lowercased speaker name. Build this once when displaying a
    /// multi-track animation so each track is an O(1) dictionary lookup instead of re-parsing and
    /// re-filtering the whole script per creature.
    public var linesBySpeaker: [String: [ScriptLine]] {
        Dictionary(grouping: parsedScriptLines, by: { $0.speaker.lowercased() })
    }
}

extension DialogProvenance.MouthCue {
    /// Servo openness (0 closed … 255 open) for this cue's shape, via the shared `MouthShape`
    /// mapping — the same value the mouth servo is driven to, so a ribbon of these reads exactly
    /// like the physical mouth.
    public var openness: UInt8 { MouthShape.openness(shape) }
}

extension DialogProvenance.LipsyncTrack {

    /// The time span covered by this track's cues (first cue start … last cue end), or `nil` when
    /// there are no cues.
    public var timeSpan: ClosedRange<Double>? {
        guard let first = cues.first?.start, let last = cues.last?.end, last >= first else {
            return nil
        }
        return first...last
    }

    /// Bake this track's mouth cues into a per-frame openness byte array (0 closed … 255 open) at
    /// the animation's frame rate — the same servo bytes a baked mouth track would carry, so the
    /// activity ribbon can render through the existing `ByteChartView` and align with the servo
    /// waveforms above it.
    public func mouthFrames(millisecondsPerFrame: UInt32, frameCount: Int) -> [UInt8] {
        let timed = cues.map {
            TimedMouthValue(start: $0.start, end: $0.end, openness: $0.openness)
        }
        return MouthShape.bakeFrames(
            timed, millisecondsPerFrame: millisecondsPerFrame, frameCount: frameCount)
    }

    /// The mouth shape active at time `seconds`, or `nil` if no cue covers it. Cues are contiguous
    /// and ordered, so a binary search finds the covering cue in O(log n) even for the thousands of
    /// cues a long dialog carries.
    public func shape(at seconds: Double) -> String? {
        var low = 0
        var high = cues.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            if seconds < cue.start {
                high = mid - 1
            } else if seconds >= cue.end {
                low = mid + 1
            } else {
                return cue.shape
            }
        }
        return nil
    }
}

extension DialogProvenance.WordTrack {

    /// The word being spoken at time `seconds`, or `nil` if none covers it. Words are ordered but —
    /// unlike mouth cues — not contiguous (there are gaps between words), so binary search finds a
    /// candidate and the half-open `[start, end)` check confirms the cursor is inside it.
    public func word(at seconds: Double) -> String? {
        var low = 0
        var high = words.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let timing = words[mid]
            if seconds < timing.start {
                high = mid - 1
            } else if seconds >= timing.end {
                low = mid + 1
            } else {
                return timing.word
            }
        }
        return nil
    }
}

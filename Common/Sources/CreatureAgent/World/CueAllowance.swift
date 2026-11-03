import WorldCore

/// The voice cues of one line as it streams, sentence by sentence (#270). The first cue is
/// performed and any later one dropped: each costs the room up to a second and a half. A
/// sentence that is only a cue waits for the next one's words, since Creature Server refuses a
/// sentence with nothing to say; a cue left at the end of the line is never spoken.
struct CueAllowance {
    private var spent = false
    private var waiting: String?

    /// The sentence to speak, or `nil` while it is only a cue.
    mutating func admit(_ sentence: String) -> String? {
        let line = VoiceCues.keepingFirst(
            [waiting, sentence].compactMap { $0 }.joined(separator: " "), allowed: !spent)
        waiting = nil
        let cues = VoiceCues.cues(in: line)
        guard !VoiceCues.words(line).trimmingCharacters(in: .whitespaces).isEmpty else {
            waiting = cues.first
            return nil
        }
        if !cues.isEmpty { spent = true }
        return line
    }
}

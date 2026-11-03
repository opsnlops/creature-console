import WorldCore

/// The voice cues of a line as it streams, sentence by sentence (#270). A bird may use as many
/// as it likes, anywhere in the line; but a sentence that is only cues waits for the next one's
/// words, since Creature Server refuses a sentence with nothing to say, and cues left at the end
/// of the line are never spoken.
struct WaitingCues {
    private var waiting: String?

    /// The sentence to speak, or `nil` while it is only cues.
    mutating func admit(_ sentence: String) -> String? {
        let line = [waiting, sentence].compactMap { $0 }.joined(separator: " ")
        guard !VoiceCues.words(line).trimmingCharacters(in: .whitespaces).isEmpty else {
            waiting = line
            return nil
        }
        waiting = nil
        return line
    }
}

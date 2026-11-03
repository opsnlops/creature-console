import Foundation

/// A voice cue: a sound or a feeling in square brackets — `[sighs]`, `[choked up with
/// happiness]` — that Creature Server's voice performs instead of saying (#270). A line's record
/// keeps its words; the line as performed, cue and all, rides beside them.
///
/// The minds' protocol tags are never cues: each carries a colon (`[learned: …]`, `[house: …]`,
/// `[quiet: …]`), and `[silence]` is the silence token. A longer bracket is narration.
public enum VoiceCues {
    public static let maximumLength = 40

    /// Every cue in `text`, in order, brackets and all.
    public static func cues(in text: String) -> [String] {
        ranges(in: text).map { String(text[$0]) }
    }

    /// The words of `text`: its cues removed, whitespace collapsed, no space left before
    /// punctuation ("Fine [sighs]." is "Fine."). A line with no cue is its own words.
    public static func words(_ text: String) -> String {
        keepingFirst(text, allowed: false)
    }

    /// `text` with at most its first cue, or none when `allowed` is false. A line with nothing
    /// to remove comes back exactly as it was.
    public static func keepingFirst(_ text: String, allowed: Bool = true) -> String {
        let removed = ranges(in: text).dropFirst(allowed ? 1 : 0)
        guard !removed.isEmpty else { return text }
        var kept = text
        for range in removed.reversed() {
            kept.replaceSubrange(range, with: " ")
        }
        return kept.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ([.,!?;:])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let pattern = #"\[[^\[\]\n:]{1,\#(maximumLength)}\]"#

    private static func ranges(in text: String) -> [Range<String.Index>] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap {
                guard let range = Range($0.range, in: text) else { return nil }
                let inside = text[range].dropFirst().dropLast()
                    .trimmingCharacters(in: .whitespaces)
                guard inside.contains(where: \.isLetter),
                    inside.caseInsensitiveCompare("silence") != .orderedSame
                else { return nil }
                return range
            }
    }
}

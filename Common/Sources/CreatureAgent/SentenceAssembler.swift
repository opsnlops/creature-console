import Foundation

/// Turns a stream of model text deltas into spoken sentences: a sentence is released at
/// ". ", "! " or "?" followed by a new sentence, wrapping quotes are dropped, `<think>` blocks
/// are skipped, and sentences shorter than `minimumCharacters` wait for the next one so the
/// speech engine never gets a fragment. Shared by every streaming model client so Beaky sounds
/// the same whichever model is thinking.
struct SentenceAssembler {
    private var buffer = ""
    private var insideThinkTag = false
    private let minimumCharacters: Int

    init(minimumCharacters: Int = 0) {
        self.minimumCharacters = minimumCharacters
    }

    /// Feed a delta; get back the sentences it completed.
    mutating func feed(_ text: String) -> [String] {
        var sentences: [String] = []
        for character in text {
            if insideThinkTag {
                buffer.append(character)
                if buffer.hasSuffix("</think>") {
                    if let range = buffer.range(of: "<think>") {
                        buffer = String(buffer[..<range.lowerBound])
                    } else {
                        buffer = ""
                    }
                    insideThinkTag = false
                }
                continue
            }
            buffer.append(character)
            if buffer.hasSuffix("<think>") {
                insideThinkTag = true
                continue
            }
            guard let split = Self.sentenceBoundaryIndex(buffer) else { continue }
            let sentence = Self.clean(String(buffer[...split]))
            let remainder = String(buffer[buffer.index(after: split)...])
            if sentence.isEmpty {
                buffer = remainder
            } else if sentence.count >= minimumCharacters {
                sentences.append(sentence)
                buffer = remainder
            }
            // Too short: the split point stays in the buffer and the next sentence joins it.
        }
        return sentences
    }

    /// Whatever is left when the stream ends, without sentence punctuation; `nil` when it is
    /// only quotes or whitespace.
    mutating func flush() -> String? {
        let remaining = Self.clean(buffer)
        buffer = ""
        return remaining.isEmpty ? nil : remaining
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The index of the sentence-ending mark when the next character starts a new sentence
    /// (space, uppercase, opening quote), handling "Hello. World" and "Hello!World" alike and
    /// a closing quote after the mark.
    static func sentenceBoundaryIndex(_ buffer: String) -> String.Index? {
        guard buffer.count >= 2 else { return nil }
        let lastIdx = buffer.index(before: buffer.endIndex)
        let lastChar = buffer[lastIdx]
        let penultIdx = buffer.index(before: lastIdx)
        let penultChar = buffer[penultIdx]
        let isPunct = { (c: Character) -> Bool in c == "." || c == "!" || c == "?" }
        let isNewSentenceStart = { (c: Character) -> Bool in
            c == " " || c.isUppercase || c == "\"" || c == "\u{201C}"
        }
        if isPunct(penultChar) && isNewSentenceStart(lastChar) {
            return penultIdx
        }
        if buffer.count >= 3 {
            let threeBackIdx = buffer.index(penultIdx, offsetBy: -1)
            if isPunct(buffer[threeBackIdx]) && (penultChar == "\"" || penultChar == "'")
                && isNewSentenceStart(lastChar)
            {
                return penultIdx
            }
        }
        return nil
    }
}

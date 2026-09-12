import Foundation

/// "Beaky, set the lights to normal evening." Recognising an ask for the house is a world
/// rule, deterministic, matched against the scenes the house has said it offers — a small
/// model cannot be trusted to call a tool, and a rule needs no model at all. The mind still
/// answers in its own voice; it is simply told the house is already doing it.
public struct SceneRequestRule: Sendable {
    /// Words that make a sentence an ask rather than a mention ("I love movie time").
    static let triggers: Set<String> = [
        "set", "switch", "turn", "make", "put", "lights", "light", "scene", "mode", "go",
    ]

    public init() {}

    /// The offered scene named in `text`, if the text is asking for it. Case- and
    /// punctuation-insensitive; the longest matching name wins ("bunnys room bedtime" over
    /// "bedtime").
    public func scene(in text: String, offered: [String]) -> String? {
        let words = Self.words(text)
        guard !words.isEmpty, !Set(words).isDisjoint(with: Self.triggers) else { return nil }
        let candidates = offered.filter { name in
            let nameWords = Self.words(name)
            return !nameWords.isEmpty && Self.contains(words, nameWords)
        }
        return candidates.max { Self.words($0).count < Self.words($1).count }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}

/// The world's hook for house asks at ingress: recognise one in the words and, if so, have
/// the house act — returning the fact the mind is told ("April just asked for Normal Evening
/// and the house is doing it") so the percept shows exactly that.
public protocol HouseCommandRecognizing: Sendable {
    func request(in utterance: PersonUtterance) async throws -> Fact?
}

public struct NoHouseCommands: HouseCommandRecognizing {
    public init() {}
    public func request(in utterance: PersonUtterance) async throws -> Fact? { nil }
}

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
        guard !words.isEmpty else { return nil }
        let candidates = offered.filter { name in
            let nameWords = Self.words(name)
            return !nameWords.isEmpty && Self.contains(words, nameWords)
        }
        guard let best = candidates.max(by: { Self.words($0).count < Self.words($1).count })
        else { return nil }
        // "@beaky normal evening" / "Goodnight, please." — the whole message is the scene's
        // name: that is an ask with no need for a verb. A name inside a longer sentence needs
        // one, or "I love movie time" would dim the lights.
        let bare = words.filter { !Self.fillers.contains($0) }
        if bare == Self.words(best) { return best }
        return Set(words).isDisjoint(with: Self.triggers) ? nil : best
    }

    /// Words that do not make a bare scene name any less bare.
    static let fillers: Set<String> = ["please", "now", "thanks", "thank", "you", "beaky", "the"]

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

/// Who decides that April is asking the house for a scene (#240): the word rule at ingress
/// (`words`), or the bird answering her, which starts its reply with `[house: Movie Time]`
/// (`mind`).
public enum HouseAskMode: String, Codable, Equatable, Sendable {
    case words
    case mind
}

/// What `GET /v1/house/asks` tells a mind: who decides, and - when it is the mind - the scenes
/// the house offers, by name.
public struct HouseAsks: Codable, Equatable, Sendable {
    public var askedBy: HouseAskMode
    /// The scenes a bird may ask for: offered by the house, and not set aside (#241).
    public var scenes: [String]
    /// What each scene is, in April's words or a draft of them; a scene may have none.
    public var descriptions: [String: String]

    public init(askedBy: HouseAskMode, scenes: [String], descriptions: [String: String] = [:]) {
        self.askedBy = askedBy
        self.scenes = scenes
        self.descriptions = descriptions
    }

    enum CodingKeys: String, CodingKey {
        case askedBy = "asked_by"
        case scenes
        case descriptions
    }

    /// A World from before descriptions sends none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        askedBy = try container.decode(HouseAskMode.self, forKey: .askedBy)
        scenes = try container.decode([String].self, forKey: .scenes)
        descriptions =
            try container.decodeIfPresent([String: String].self, forKey: .descriptions) ?? [:]
    }

    /// The offered scene `name` is, by any capitalisation and spacing; nil when it is none.
    public func scene(named name: String) -> String? {
        let wanted = Self.key(name)
        return scenes.first { Self.key($0) == wanted }
    }

    private static func key(_ name: String) -> String {
        // "Bunny's Room" is "Bunnys Room": an apostrophe is part of a word, not a gap.
        name.lowercased().filter { $0 != "'" && $0 != "\u{2019}" }
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}

/// One of the house's scenes as the world describes it (#241): what it is, and whether a bird
/// may ask for it - a scene an automation or a wall button runs is not for asking.
public struct HouseScene: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var askable: Bool
    /// Whether the house offers it now; a described scene the house dropped stays listed.
    public var offered: Bool
    /// nil for a scene nobody has described yet.
    public var updatedAt: Date?
    public var updatedBy: String?

    public init(
        name: String, description: String = "", askable: Bool = true, offered: Bool = true,
        updatedAt: Date? = nil, updatedBy: String? = nil
    ) {
        self.name = name
        self.description = description
        self.askable = askable
        self.offered = offered
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    enum CodingKeys: String, CodingKey {
        case name, description, askable, offered
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }
}

public struct HouseScenePage: Codable, Equatable, Sendable {
    public var scenes: [HouseScene]

    public init(scenes: [HouseScene]) { self.scenes = scenes }
}

/// A scene described: by April in the Viewer, or by the world's drafts.
public struct HouseSceneUpdate: Codable, Equatable, Sendable {
    public var description: String
    public var askable: Bool
    public var updatedBy: String

    public init(description: String, askable: Bool, updatedBy: String) {
        self.description = description
        self.askable = askable
        self.updatedBy = updatedBy
    }

    enum CodingKeys: String, CodingKey {
        case description, askable
        case updatedBy = "updated_by"
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

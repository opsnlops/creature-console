import Foundation
import WorldCore
import Yams

/// Who a character is, as April writes it: a versioned file per bird
/// (`docs/personas/<bird>.yaml`, deployed to `/etc/creature/agent/personas/`). Personality
/// lives here and nowhere else — the world supplies occasions and facts, the persona supplies
/// the voice. Every field but `name` and `about` is optional so a bird can start as two lines.
struct Persona: Decodable, Equatable, Sendable {
    let name: String
    let version: Int
    let pronouns: String?
    /// Who this character is, in a paragraph or two.
    let about: String
    /// How they talk: length, tone, tics.
    let voice: String?
    let caresAbout: [String]
    let avoids: [String]
    /// How this character feels about someone, by entity ID (`character:mango`, `person:april`).
    /// Only the ones actually present are rendered.
    let relationships: [String: Relationship]
    let runningJokes: [String]
    /// Hard rules, rendered last so they are the freshest thing the model has read.
    let never: [String]

    /// What this character thinks of someone: the feeling, and — as this character believes
    /// them — the other's pronouns. The world's own `identity.pronouns` fact, when it has one,
    /// outranks this: a bird's pronouns are that bird's to state.
    struct Relationship: Decodable, Equatable, Sendable {
        let feeling: String
        let pronouns: String?

        init(feeling: String, pronouns: String? = nil) {
            self.feeling = feeling
            self.pronouns = pronouns
        }

        private enum CodingKeys: String, CodingKey { case feeling, pronouns }

        /// `character:mango: "Computer geek."` or
        /// `character:mango: {pronouns: he/him, feeling: "Computer geek."}`.
        init(from decoder: any Decoder) throws {
            if let feeling = try? decoder.singleValueContainer().decode(String.self) {
                self.init(feeling: feeling.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                feeling: try container.decode(String.self, forKey: .feeling)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                pronouns: try container.decodeIfPresent(String.self, forKey: .pronouns))
        }
    }

    /// `name/version`, on every span as `agent.persona_version`.
    var versionTag: String { "\(name.lowercased())/\(version)" }

    private enum CodingKeys: String, CodingKey {
        case name, version, pronouns, about, voice
        case caresAbout = "cares_about"
        case avoids, relationships
        case runningJokes = "running_jokes"
        case never
    }

    init(
        name: String, version: Int = 1, pronouns: String? = nil, about: String,
        voice: String? = nil, caresAbout: [String] = [], avoids: [String] = [],
        relationships: [String: Relationship] = [:], runningJokes: [String] = [],
        never: [String] = []
    ) {
        self.name = name
        self.version = version
        self.pronouns = pronouns
        self.about = about
        self.voice = voice
        self.caresAbout = caresAbout
        self.avoids = avoids
        self.relationships = relationships
        self.runningJokes = runningJokes
        self.never = never
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        pronouns = try container.decodeIfPresent(String.self, forKey: .pronouns)
        about = try container.decode(String.self, forKey: .about)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        voice = try container.decodeIfPresent(String.self, forKey: .voice)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        caresAbout = try container.decodeIfPresent([String].self, forKey: .caresAbout) ?? []
        avoids = try container.decodeIfPresent([String].self, forKey: .avoids) ?? []
        relationships =
            try container.decodeIfPresent([String: Relationship].self, forKey: .relationships)
            ?? [:]
        runningJokes = try container.decodeIfPresent([String].self, forKey: .runningJokes) ?? []
        never = try container.decodeIfPresent([String].self, forKey: .never) ?? []
        guard !name.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: container, debugDescription: "a persona needs a name")
        }
        guard !about.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .about, in: container,
                debugDescription: "a persona needs an `about`: who is this character?")
        }
        guard version > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container, debugDescription: "version must be positive")
        }
    }

    static func load(from url: URL) throws -> Persona {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(Persona.self, from: contents)
    }

    /// The persona as the model reads it, in sections, mentioning only the people who are
    /// actually here: a relationship with someone absent is noise the model would act on.
    /// Deterministic — the same persona and company always render the same text — so a
    /// persona edit reviews as a diff of what the model sees.
    func rendered(present: [EntityID], pronouns known: [EntityID: String] = [:]) -> String {
        var sections: [String] = []
        var who = "You are \(name)"
        if let pronouns { who += " (\(pronouns))" }
        who += ". " + about
        sections.append(who)
        if let voice, !voice.isEmpty {
            sections.append("How you talk: " + voice)
        }
        if !caresAbout.isEmpty {
            sections.append("You care about: " + Self.list(caresAbout) + ".")
        }
        if !avoids.isEmpty {
            sections.append("You steer away from: " + Self.list(avoids) + ".")
        }
        let company = present.compactMap { id -> String? in
            guard let relationship = relationships[id.rawValue] else { return nil }
            let pronouns = known[id] ?? relationship.pronouns
            return "- \(FactPhrasing.name(of: id, pronouns: pronouns)): \(relationship.feeling)"
        }
        if !company.isEmpty {
            sections.append(
                "The ones here, and how you feel about them:\n" + company.joined(separator: "\n"))
        }
        if !runningJokes.isEmpty {
            sections.append("Running jokes: " + Self.list(runningJokes) + ".")
        }
        if !never.isEmpty {
            sections.append("Never: " + Self.list(never) + ".")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func list(_ items: [String]) -> String {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            .joined(separator: "; ")
    }
}

/// What a mind is: April's structured persona, or — for a mind not yet given one — the plain
/// `llmSystemPrompt` it has always had.
enum CharacterPersona: Equatable, Sendable {
    case structured(Persona)
    case text(String)

    var versionTag: String {
        switch self {
        case .structured(let persona): persona.versionTag
        case .text: "system-prompt"
        }
    }

    var pronouns: String? {
        switch self {
        case .structured(let persona): persona.pronouns
        case .text: nil
        }
    }

    func rendered(present: [EntityID], pronouns: [EntityID: String] = [:]) -> String {
        switch self {
        case .structured(let persona): persona.rendered(present: present, pronouns: pronouns)
        case .text(let text): text
        }
    }
}

import Foundation
import WorldCore

/// Something April told a bird that the world should keep: "Jesse's coming Tuesday to finish the
/// deck", "no Beaky, that was just the postman". The mind ends its reply with one tag per thing,
/// `[learned: subject | predicate | value | expires]`; the tags are never spoken, and each becomes
/// a `facts.given` cast with April as the source and her words as provenance. Only what April
/// said, never a guess: "the virtual world can guess, but the real world knows."
struct LearnedFact: Equatable, Sendable {
    enum Expiry: String, CaseIterable, Sendable {
        case today, tomorrow, week, never

        /// Seconds from `now` until the fact stops holding, in the house's zone.
        func seconds(from now: Date, in timeZone: TimeZone) -> TimeInterval? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let startOfToday = calendar.startOfDay(for: now)
            switch self {
            case .today:
                return calendar.date(byAdding: .day, value: 1, to: startOfToday)!
                    .timeIntervalSince(now)
            case .tomorrow:
                return calendar.date(byAdding: .day, value: 2, to: startOfToday)!
                    .timeIntervalSince(now)
            case .week: return 7 * 86_400
            case .never: return nil
            }
        }
    }

    var subjectID: EntityID
    var predicate: String
    var value: String
    var expiry: Expiry

    static let tagPattern = #"\[learned:([^\]]*)\]"#
    static let maximumPerReply = 3

    /// Every well-formed tag in the model's raw output, in order, at most `maximumPerReply`.
    /// A tag names its subject as the mind sees it — "Jesse", "the front door", "the house" —
    /// and it is turned into the world's entity here.
    static func all(in raw: String, names: EntityNames) -> [LearnedFact] {
        guard let expression = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        let range = NSRange(raw.startIndex..., in: raw)
        var facts: [LearnedFact] = []
        for match in expression.matches(in: raw, range: range) {
            guard let inner = Range(match.range(at: 1), in: raw),
                let fact = parse(String(raw[inner]), names: names)
            else { continue }
            facts.append(fact)
            if facts.count == maximumPerReply { break }
        }
        return facts
    }

    /// The text with every tag removed, so nothing of it is ever spoken.
    static func stripped(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: tagPattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Strips tags from text that arrives a sentence at a time: a tag cut by the sentence
    /// splitter ("[learned: April | medical.labs | getting labs now." / "| today]") is
    /// dropped across the pieces, `inTag` carrying the cut from one piece to the next.
    static func strippedStreaming(_ text: String, inTag: inout Bool) -> String {
        var result = ""
        var rest = Substring(text)
        while !rest.isEmpty {
            if inTag {
                guard let close = rest.firstIndex(of: "]") else { return result }
                rest = rest[rest.index(after: close)...]
                inTag = false
                continue
            }
            guard let open = rest.range(of: "[learned:") else {
                result += rest
                return result
            }
            result += rest[..<open.lowerBound]
            rest = rest[open.upperBound...]
            inTag = true
        }
        return result
    }

    static func parse(_ inner: String, names: EntityNames) -> LearnedFact? {
        let parts = inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 4, let subject = names.entity(named: parts[0]),
            isPredicate(parts[1]), !parts[2].isEmpty, parts[2].count <= 200,
            let expiry = Expiry(rawValue: parts[3].lowercased())
        else { return nil }
        return LearnedFact(
            subjectID: subject, predicate: parts[1].lowercased(), value: parts[2], expiry: expiry)
    }

    static func isPredicate(_ text: String) -> Bool {
        let parts = text.split(separator: ".")
        return parts.count == 2
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0 == "_" } }
    }

    /// The contract's paragraph: what to tag, and what never to.
    static let contract = """
        When April tells you something worth keeping - who someone is, that someone is expected \
        and when, that a sighting was her or the postman, a correction to something you said - \
        end your reply with one line per thing, exactly [learned: who, where, or what | predicate \
        | value | expires], for example [learned: Jesse | visitor.expected | Tuesday afternoon, to \
        finish the deck | tomorrow] or [learned: the front door | sighting.identified | the \
        postman | today]. Name the subject by its kind: a person by name ("Jesse"), a place with \
        "the" ("the kitchen"), a bird by name ("Kenny"), anything else as "thing: Mac Studio", \
        and one of April's spells - what she builds to let you notice or do something - as \
        "spell: the TV spell". One subject per line: never "Kenny and Mango" or "all three \
        birds". Predicates: a kind from "what those kinds of fact mean" when one fits, else one already on \
        that subject, else a short dotted word of your own. If another bird has already kept the \
        same thing in this scene, do not keep it again. Expires: today, tomorrow, week, or never. \
        Only what April actually said, never your own guess; at most three; the tags are for the \
        world's record and are never spoken.
        """
}

/// Who a name in a mind's words refers to. The birds are known by name - "Kenny" is
/// `character:kenny`, never a person - the house by "the house", and everyone else is a person
/// or, by its words, a place. Both the learned tags and the nightly memory resolve through this.
struct EntityNames: Sendable {
    let houseID: EntityID
    private(set) var characters: [String: EntityID] = [:]
    /// Every entity the mind was shown, by its slug: a name it learns something about that
    /// the world already holds - "Information Bridge" when `thing:information-bridge` is in
    /// the facts - is that entity, whatever kind the mind wrote. The world knows; the mind
    /// guesses.
    private(set) var known: [String: EntityID] = [:]

    init(houseID: EntityID, characters: [EntityID] = [], known: [EntityID] = []) {
        self.houseID = houseID
        add(characters)
        add(known)
    }

    /// Adds every id: a `character:` by its name too, everything by its slug. The first id
    /// for a slug stands; the birds and the house are added first.
    mutating func add(_ ids: [EntityID]) {
        for id in ids {
            if id.rawValue.hasPrefix("character:") {
                characters[Self.key(FactPhrasing.name(of: id))] = id
            }
            if let colon = id.rawValue.firstIndex(of: ":") {
                let slug = String(id.rawValue[id.rawValue.index(after: colon)...])
                // A slug the world holds under two kinds is the one that is not the old
                // default: `person:mac-studio` was a guess, `thing:mac-studio` is what it is.
                if let held = known[slug] {
                    if held.rawValue.hasPrefix("person:"), !id.rawValue.hasPrefix("person:") {
                        known[slug] = id
                    }
                } else {
                    known[slug] = id
                }
            }
        }
    }

    /// The kinds a mind may name outright: "thing: Hopper" is `thing:hopper`, a named car,
    /// computer, or printer - not a person; "spell: the TV spell" is `spell:tv-spell`, one of
    /// April's spells (the world is a wizard rabbit's and her familiar's: what she builds for
    /// the birds, they call spells).
    static let kinds: Set<String> = ["person", "place", "house", "character", "thing", "spell"]

    /// Words that never make a person's name: a bare "Mac Studio" or "Mukilteo Clinton Ferry"
    /// is a thing, however capitalized. Anything unfamiliar used to fall through to `person:`,
    /// and fifty things - servers, chargers, the ferry, "new spell" - became people.
    static let thingWords: Set<String> = [
        "server", "servers", "studio", "mac", "charger", "printer", "car", "truck", "van",
        "ferry", "bridge", "viewer", "world", "order", "delivery", "package", "card", "cards",
        "camera", "cameras", "motor", "motors", "pico", "picos", "screws", "board", "boards",
        "animation", "animations", "animatronic", "animatronics", "event", "calendar", "labs",
        "travel", "conversation", "spell", "spells", "tv", "speaker", "sound", "flock",
        "birds", "system", "app", "network", "congregation", "church", "park",
    ]

    /// "Jesse" → `person:jesse`; "the front door" → `place:front-door`; "the house" → the
    /// configured house; "Mango" → `character:mango` when Mango is known; "thing: Hopper" or
    /// an id the mind already wrote (`person:jesse`) → that kind, the name made a slug.
    func entity(named name: String) -> EntityID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = trimmed.firstIndex(of: ":") {
            let kind = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard Self.kinds.contains(kind),
                let slug = Self.slug(String(trimmed[trimmed.index(after: colon)...]))
            else { return nil }
            if kind == "house" { return houseID }
            // The world already holds this name under a kind: that one, not the mind's.
            if let existing = known[slug], !Self.isMisfiledPerson(existing, name: trimmed) {
                return existing
            }
            // "person: Creature Server" - a record from before spells, copied back - is not
            // a person because it says so; a person's name has to look like one.
            if kind == "person",
                slug.split(separator: "-").contains(where: { Self.thingWords.contains(String($0)) })
            {
                return EntityID(rawValue: "thing:\(slug)")
            }
            return EntityID(rawValue: "\(kind):\(slug)")
        }
        if let character = characters[Self.key(trimmed)] { return character }
        // A group is not an entity: "Kenny and Mango", "all three birds" - nobody to file it on.
        let lowered = " " + trimmed.lowercased() + " "
        if lowered.contains(" and ") || lowered.contains(" all ") || trimmed.contains(",") {
            return nil
        }
        guard let slug = Self.slug(trimmed) else { return nil }
        if slug == "house" { return houseID }
        if let existing = known[slug], !Self.isMisfiledPerson(existing, name: trimmed) {
            return existing
        }
        let words = slug.split(separator: "-").map(String.init)
        let placeWords: Set<String> = [
            "door", "driveway", "carport", "kitchen", "workshop", "orchard", "porch", "garage",
            "entryway", "room", "yard", "deck", "outside", "gate", "bedroom", "bathroom", "office",
        ]
        if words.contains(where: { placeWords.contains($0) }) {
            return EntityID(rawValue: "place:\(slug)")
        }
        return EntityID(rawValue: "\(Self.looksLikeAPerson(trimmed) ? "person" : "thing"):\(slug)")
    }

    /// A `person:` the world holds that is really a thing - filed before spells, when anything
    /// unfamiliar became a person: its slug carries a word that names things.
    static func isMisfiledPerson(_ id: EntityID, name: String) -> Bool {
        guard id.rawValue.hasPrefix("person:") else { return false }
        let slugWords = id.rawValue.dropFirst("person:".count).split(separator: "-")
        return slugWords.contains { thingWords.contains(String($0)) }
    }

    /// A name a person could have: one or two capitalized words, no "the", no possessive, no
    /// digits, and none of the words that name things. "Tamara", "Adlai Erickson" - yes;
    /// "new spell", "Mac Studio", "April's bedroom" - no.
    static func looksLikeAPerson(_ name: String) -> Bool {
        let words = name.split(separator: " ").map(String.init)
        guard (1...2).contains(words.count), words.first?.lowercased() != "the",
            !name.contains("'"), !name.contains("’"), !name.contains(where: \.isNumber)
        else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return !thingWords.contains(word.lowercased())
        }
    }

    /// The same, but only for an entity the world already holds - the house, a bird, or a
    /// name that has facts. A belief about nobody the record names is no belief.
    func knownEntity(named name: String) -> EntityID? {
        guard let id = entity(named: name) else { return nil }
        if id == houseID || characters.values.contains(id) || known.values.contains(id) {
            return id
        }
        return nil
    }

    /// "The Front Door" → `front-door`; nothing, or more than four words, is no name.
    private static func slug(_ name: String) -> String? {
        var words = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        if words.first == "the" { words.removeFirst() }
        guard !words.isEmpty, words.count <= 4 else { return nil }
        return words.joined(separator: "-")
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }


}

import Foundation
import WorldCore

/// Something April told a bird that the world should keep: "Jesse's coming Tuesday to finish the
/// deck", "no Beaky, that was just the postman". The mind ends its reply with one tag per thing,
/// `[learned: subject | predicate | value | expires]`; the tags are never spoken, and each becomes
/// a `facts.given` cast with April as the source and her words as provenance. Only what April
/// said, never a guess: "the virtual world can guess, but the real world knows."
struct LearnedFact: Equatable, Sendable {
    enum Expiry: Equatable, Sendable {
        case today, tomorrow, week, never
        /// A span from now: "1h", "30m" - "ignore the cameras for the next hour" (#220). At
        /// most twelve hours, so a slip of the tongue cannot silence a house for days.
        case span(TimeInterval)

        static let longestSpan: TimeInterval = 12 * 3_600

        /// "today", "1h", "30m"; nil for anything else.
        init?(word: String) {
            let word = word.lowercased().trimmingCharacters(in: .whitespaces)
            switch word {
            case "today": self = .today
            case "tomorrow": self = .tomorrow
            case "week": self = .week
            case "never": self = .never
            default:
                guard let unit = word.last, "hm".contains(unit),
                    let amount = Int(word.dropLast()), amount > 0
                else { return nil }
                let seconds = TimeInterval(amount) * (unit == "h" ? 3_600 : 60)
                guard seconds <= Self.longestSpan else { return nil }
                self = .span(seconds)
            }
        }

        /// As the tag wrote it, for the logs.
        var word: String {
            switch self {
            case .today: "today"
            case .tomorrow: "tomorrow"
            case .week: "week"
            case .never: "never"
            case .span(let seconds):
                seconds.truncatingRemainder(dividingBy: 3_600) == 0
                    ? "\(Int(seconds / 3_600))h" : "\(Int(seconds / 60))m"
            }
        }

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
            case .span(let seconds): return seconds
            }
        }
    }

    var subjectID: EntityID
    var predicate: String
    var value: String
    var expiry: Expiry

    /// A value of `none` ends the fact instead of setting it: "he's gone now" is
    /// `[learned: Jesse | visitor.expected | none | today]`. Before this there was no way to
    /// take a fact back, and a visitor April had said was gone stayed "expected" all evening -
    /// every camera sighting was "either her or Jesse", and the birds kept asking.
    static let endingWords: Set<String> = ["none", "gone", "nothing", "no longer"]
    var ends: Bool { Self.endingWords.contains(value.lowercased()) }

    static let tagPattern = #"\[learned:([^\]]*)\]"#
    static let maximumPerReply = 3

    /// One tag as the mind wrote it, its subject not yet an entity.
    struct Tag: Equatable, Sendable {
        var name: String
        var predicate: String
        var value: String
        var expiry: Expiry

        func fact(on subject: EntityID) -> LearnedFact {
            LearnedFact(subjectID: subject, predicate: predicate, value: value, expiry: expiry)
        }
    }

    /// Every well-formed tag in the model's raw output, in order, at most `maximumPerReply`.
    static func tags(in raw: String) -> [Tag] {
        guard let expression = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        let range = NSRange(raw.startIndex..., in: raw)
        var tags: [Tag] = []
        for match in expression.matches(in: raw, range: range) {
            guard let inner = Range(match.range(at: 1), in: raw),
                let tag = tag(String(raw[inner]))
            else { continue }
            tags.append(tag)
            if tags.count == maximumPerReply { break }
        }
        return tags
    }

    /// The tags whose subjects resolve, and the names that did not. A tag names its subject as
    /// the mind sees it - "person: Jesse", "the house", "Kenny" - and a bare name the world
    /// does not hold is judged by `judge` from the tag, the conversation around it, and the
    /// reply it came in. April: "add in some of the conversation that was happening around the
    /// word."
    static func all(
        in raw: String, names: EntityNames, judge: (any EntityKindJudging)?,
        conversation: String = ""
    ) async -> (facts: [LearnedFact], unnamed: [String]) {
        let reply = stripped(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let context = conversation.isEmpty ? reply : "\(conversation)\n\nThe reply: \(reply)"
        var facts: [LearnedFact] = []
        var unnamed: [String] = []
        for tag in tags(in: raw) {
            let line = "[learned: \(tag.name) | \(tag.predicate) | \(tag.value)]\n\(context)"
            guard let subject = await names.resolve(tag.name, context: line, judge: judge) else {
                unnamed.append(tag.name)
                continue
            }
            facts.append(tag.fact(on: subject))
        }
        return (facts, unnamed)
    }

    /// The tags whose subjects resolve without asking anyone.
    static func all(in raw: String, names: EntityNames) -> [LearnedFact] {
        tags(in: raw).compactMap { tag in names.entity(named: tag.name).map(tag.fact(on:)) }
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

    static func tag(_ inner: String) -> Tag? {
        let parts = inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 4, !parts[0].isEmpty, isPredicate(parts[1]), !parts[2].isEmpty,
            parts[2].count <= 200, let expiry = Expiry(word: parts[3])
        else { return nil }
        return Tag(
            name: parts[0], predicate: parts[1].lowercased(), value: parts[2], expiry: expiry)
    }

    static func parse(_ inner: String, names: EntityNames) -> LearnedFact? {
        guard let tag = tag(inner), let subject = names.entity(named: tag.name) else { return nil }
        return tag.fact(on: subject)
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
        | value | expires], for example [learned: person: Jesse | visitor.expected | Tuesday afternoon, \
        to finish the deck | tomorrow] or [learned: place: the front door | sighting.identified | \
        the postman | today]. Name the subject with its kind: "person: Jesse", "place: the kitchen", \
        "place: Rocket Taco" for a restaurant or shop, "thing: Mac Studio" for an object, app, \
        or organization, and one of April's spells - what she builds to let you notice or do \
        something - as "spell: the TV spell"; a bird by its name alone ("Kenny"), and the house \
        as "the house". One subject per line: never "Kenny and Mango" or "all three \
        birds". Someone already here is kept for as long as a visit like theirs takes, never \
        the whole day: [learned: thing: propane supplier | visitor.expected | here now, \
        refilling the big tank | 2h]. When April says something no longer holds - a visitor has \
        left, a plan is off - end it on them with the value none: [learned: person: Jesse | \
        visitor.expected | none | today]; a note on the place a camera saw does not end a visit. \
        Predicates: a kind from "what those kinds of fact mean" when one fits, else one already on \
        that subject, else a short dotted word of your own. Name the family by the topic, not by \
        who it is about: flight.landings, never person.flight_landings. A name holds one value, \
        and keeping it again replaces it: to add to a fact you can see, keep the whole of it, \
        old and new together; for something else on the same topic, use another name in the \
        same family. If another bird has already kept the \
        same thing in this scene, do not keep it again. When April asks you to let the cameras \
        be for a while, keep that too, so the house stops offering them: [learned: the house | \
        house.cameras_quiet | the yard guy is working | 1h] - and end it with none when she says \
        you may talk about them again. Expires: today, tomorrow, week, never, or a span such as \
        1h or 30m (at most 12h). \
        Only what April actually said, never your own guess; at most three; the tags are for the \
        world's record and are never spoken.
        """
}

/// Who a name in a mind's words refers to. The mind says the kind - "person: Jesse", "place:
/// Rocket Taco" - and the world's own ids win over it: a name the world already holds is that
/// entity. A bird is known by its name and the house as "the house". Nothing here guesses a
/// kind from the words of a name: a bare name nobody holds is `.unknown`, for a model to judge
/// (#239, docs/entity-kinds-plan.md). Both the learned tags and the nightly memory resolve
/// through this.
struct EntityNames: Sendable {
    let houseID: EntityID
    private(set) var characters: [String: EntityID] = [:]
    /// Every entity the mind was shown, by its slug: a name it learns something about that
    /// the world already holds - "Information Bridge" when `thing:information-bridge` is in
    /// the facts - is that entity, whatever kind the mind wrote. The world knows; the mind
    /// guesses.
    private(set) var known: [String: EntityID] = [:]

    /// What a name is, before anyone is asked.
    enum Naming: Equatable, Sendable {
        /// The house, a bird, an id the world holds, or a new name with its kind said.
        case entity(EntityID)
        /// A bare name nobody holds: its kind is a judgement.
        case unknown(slug: String)
        /// Not a name: empty, too long, or a kind no entity has.
        case none
    }

    init(houseID: EntityID, characters: [EntityID] = [], known: [EntityID] = []) {
        self.houseID = houseID
        add(characters)
        add(known)
    }

    /// Adds every id: a `character:` by its name too, everything by its slug. The first id
    /// for a slug stands; the birds and the house are added first.
    mutating func add(_ ids: [EntityID]) {
        for id in ids {
            // Only the world's entities are names; a source - `wizard:april`, `mind:beaky`,
            // `bridge:mail` - never is. The record of a day carries sources beside subjects,
            // and `wizard:april` once took April's own slug: two nights of memories about her
            // were filed where no mind is ever handed them.
            guard let colon = id.rawValue.firstIndex(of: ":"),
                Self.kinds.contains(String(id.rawValue[..<colon]))
                    || WorldFacts.linkKinds.contains(String(id.rawValue[..<colon]))
            else { continue }
            if id.rawValue.hasPrefix("character:") {
                characters[Self.key(FactPhrasing.name(of: id))] = id
            }
            let slug = String(id.rawValue[id.rawValue.index(after: colon)...])
            if known[slug] == nil { known[slug] = id }
        }
    }

    /// The kinds a mind may name outright: "thing: Hopper" is `thing:hopper`, a named car,
    /// computer, or printer; "spell: the TV spell" is `spell:tv-spell`, one of April's spells
    /// (the world is a wizard rabbit's and her familiar's: what she builds for the birds, they
    /// call spells).
    static let kinds: Set<String> = ["person", "place", "house", "character", "thing", "spell"]
    /// The kinds a judgement may give a new name.
    static let judgedKinds: Set<String> = ["person", "place", "thing", "spell"]

    /// "person: Jesse" → `person:jesse`, "place: the kitchen" → `place:kitchen`, "the house" →
    /// the configured house, "Mango" → `character:mango` when Mango is known, "Information
    /// Bridge" → `thing:information-bridge` when the world holds it; a bare "Jesse" nobody
    /// holds is `.unknown`.
    func naming(_ name: String) -> Naming {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = trimmed.firstIndex(of: ":") {
            let kind = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard Self.kinds.contains(kind),
                let slug = Self.slug(String(trimmed[trimmed.index(after: colon)...]))
            else { return .none }
            if kind == "house" { return .entity(houseID) }
            // The world already holds this name under a kind: that one, not the mind's.
            if let existing = known[slug] { return .entity(existing) }
            if kind == "character" {
                return characters[slug].map { .entity($0) } ?? .none
            }
            return EntityID(rawValue: "\(kind):\(slug)").map { .entity($0) } ?? .none
        }
        if let character = characters[Self.key(trimmed)] { return .entity(character) }
        guard let slug = Self.slug(trimmed) else { return .none }
        if slug == "house" { return .entity(houseID) }
        if let existing = known[slug] { return .entity(existing) }
        return .unknown(slug: slug)
    }

    /// The entity a name is, without asking anyone: nil for a bare name nobody holds.
    func entity(named name: String) -> EntityID? {
        if case .entity(let id) = naming(name) { return id }
        return nil
    }

    /// The entity a name is, asking `judge` what kind a bare new name is, from the line it
    /// came in. Nil when it is nobody, when there is no judge, or when the judge could not
    /// say: a fact left unfiled is better than one filed on a guess.
    func resolve(_ name: String, context: String, judge: (any EntityKindJudging)?) async
        -> EntityID?
    {
        switch naming(name) {
        case .entity(let id): return id
        case .none: return nil
        case .unknown(let slug):
            guard let judge,
                let kind = try? await judge.kind(of: name, in: context),
                Self.judgedKinds.contains(kind)
            else { return nil }
            return EntityID(rawValue: "\(kind):\(slug)")
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

/// `[house: Movie Time]`: a bird asking the house for one of its scenes, at the start of its
/// reply to April (#240). Never spoken; the world sets the scene when it arrives.
enum HouseTag {
    static let pattern = #"\[house:\s*([^\]]+?)\s*\]"#

    /// The scene the first tag in `text` asks for; nil when there is none.
    static func scene(in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        // A tag cut across two streamed pieces has a line break in it.
        let scene = text[range].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return scene.isEmpty ? nil : scene
    }

    /// The contract, when the bird decides house asks: the scenes, and how to ask for one.
    static func contract(_ asks: HouseAsks?) -> String {
        guard let asks, asks.askedBy == .mind, !asks.scenes.isEmpty else { return "" }
        // Each with what it is, when the world knows (#241): "Sleepy Time" dims the outside
        // lights for the neighbors, and its name alone offered it for "cozy".
        let scenes = asks.scenes.map { name in
            asks.descriptions[name].map { "- \(name): \($0)" } ?? "- \(name)"
        }.joined(separator: "\n")
        return """
            The house's lighting scenes, and what each does:
            \(scenes)
            When April \
            asks you to set one of them now - however she puts it: "make the evening normal" is \
            Normal Evening, "lower the key" is Low Key - start your reply with [house: the \
            scene's exact name from that list], then answer her as you would; the house sets \
            it the moment it reads the tag, and the tag is never spoken. Not when she only \
            mentions or remembers a scene, and never one she did not ask for; if it is unclear \
            which she means, ask her instead. One scene at most.
            """
    }
}

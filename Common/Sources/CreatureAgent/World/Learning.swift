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
    static func all(in raw: String, houseID: EntityID) -> [LearnedFact] {
        guard let expression = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        let range = NSRange(raw.startIndex..., in: raw)
        var facts: [LearnedFact] = []
        for match in expression.matches(in: raw, range: range) {
            guard let inner = Range(match.range(at: 1), in: raw),
                let fact = parse(String(raw[inner]), houseID: houseID)
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

    static func parse(_ inner: String, houseID: EntityID) -> LearnedFact? {
        let parts = inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 4, let subject = entity(named: parts[0], houseID: houseID),
            isPredicate(parts[1]), !parts[2].isEmpty, parts[2].count <= 200,
            let expiry = Expiry(rawValue: parts[3].lowercased())
        else { return nil }
        return LearnedFact(
            subjectID: subject, predicate: parts[1].lowercased(), value: parts[2], expiry: expiry)
    }

    /// "Jesse" → `person:jesse`; "the front door" → `place:front-door`; "the house" → the
    /// configured house; an id the mind already wrote (`person:jesse`) is taken as is.
    static func entity(named name: String, houseID: EntityID) -> EntityID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":"), let id = EntityID(rawValue: trimmed.lowercased()) {
            let prefix = trimmed.lowercased().prefix { $0 != ":" }
            return ["person", "place", "house"].contains(prefix) ? id : nil
        }
        var words = trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        if words.first == "the" { words.removeFirst() }
        guard !words.isEmpty, words.count <= 4 else { return nil }
        if words == ["house"] { return houseID }
        let slug = words.joined(separator: "-")
        let placeWords: Set<String> = [
            "door", "driveway", "carport", "kitchen", "workshop", "orchard", "porch", "garage",
            "entryway", "room", "yard", "deck", "outside", "gate",
        ]
        let kind = words.contains(where: placeWords.contains) ? "place" : "person"
        return EntityID(rawValue: "\(kind):\(slug)")
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
        end your reply with one line per thing, exactly [learned: who or where | predicate | value \
        | expires], for example [learned: Jesse | visitor.expected | Tuesday afternoon, to finish \
        the deck | tomorrow] or [learned: the front door | sighting.identified | the postman | \
        today]. Predicates: person.description, visitor.expected, sighting.identified, or a short \
        dotted word of your own. Expires: today, tomorrow, week, or never. Only what April \
        actually said, never your own guess; at most three; the tags are for the world's record \
        and are never spoken.
        """
}

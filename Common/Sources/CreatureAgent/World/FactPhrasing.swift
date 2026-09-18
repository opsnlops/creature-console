import Foundation
import WorldCore

/// Turns the world's facts into the plain sentences a character can think with. The model
/// never sees `presence.region`; it sees "Mango is here in the room with you".
enum FactPhrasing {
    /// Whether the world says `person` is home: true, false, or nil when it has no idea.
    static func isHome(_ person: EntityID, in facts: [Fact]) -> Bool? {
        presence(of: person, in: facts)?.home
    }

    /// The world's word on where `person` is, and since when - so a mind can tell "home for
    /// hours" from "came home six minutes ago", which is the moment a person at the door is
    /// her.
    static func presence(of person: EntityID, in facts: [Fact]) -> (home: Bool, since: Date)? {
        guard
            let fact = facts.first(where: {
                $0.subjectID == person && $0.predicate == WorldFacts.personState
            }), case .string(let state) = fact.value
        else { return nil }
        switch state {
        case "home": return (true, fact.validFrom)
        case "away": return (false, fact.validFrom)
        default: return nil
        }
    }

    /// The "What you know" lines for a character, newest fact first. One shape for every fact —
    /// who or where, the predicate, its value, since when, how it is known — so a new kind of
    /// fact needs a meaning in the world's glossary, never a phrasing here. A frontier model
    /// reads `The front door · door.lock = unlocked · since 8:03 PM (5 minutes ago) · observed`
    /// and says "the front door's been unlocked since eight" in its own words.
    static func lines(
        for facts: [Fact],
        character: EntityID,
        now: Date,
        in timeZone: TimeZone
    ) -> [String] {
        var lines = facts.compactMap { line(for: $0, character: character, now: now, in: timeZone) }
        // Cameras that are watching and have seen nothing: silence is a fact, said once for
        // all of them, so "is something outside?" gets an answer instead of a shrug.
        let watched = facts.filter { $0.predicate == WorldFacts.cameraWatching }
            .map(\.subjectID)
        let seen = Set(
            facts.filter { $0.predicate.hasPrefix(WorldFacts.seenPrefix) }.map(\.subjectID))
        let quiet = watched.filter { !seen.contains($0) }
        if !quiet.isEmpty {
            let names = quiet.map { placeName(of: $0).lowercased() }
            let list =
                names.count == 1
                ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
            lines.append(
                "The camera\(names.count == 1 ? "" : "s") at \(list) \(names.count == 1 ? "has" : "have") seen nobody and nothing in the last ten minutes."
            )
        }
        // A person the world can only describe in one phrase is a blank to be left blank.
        let described = facts.filter { $0.predicate == WorldFacts.personDescription }
        for fact in described
        where facts.filter({ $0.subjectID == fact.subjectID }).count == 1 {
            lines.append(
                "That is all you know about \(name(of: fact.subjectID)); do not make up more.")
        }
        return lines
    }

    /// Who uses which pronouns, from `identity.pronouns` facts.
    static func pronouns(in facts: [Fact]) -> [EntityID: String] {
        var pronouns: [EntityID: String] = [:]
        for fact in facts where fact.predicate == WorldFacts.characterPronouns {
            if case .string(let text) = fact.value { pronouns[fact.subjectID] = text }
        }
        return pronouns
    }

    /// A fact that is not for saying: pronouns ride with names, audibility is the router's,
    /// a watching camera is folded into the quiet-cameras line, and a bird knows where it is.
    private static func isUnspoken(_ fact: Fact, character: EntityID) -> Bool {
        fact.predicate == WorldFacts.characterPronouns
            || fact.predicate == WorldFacts.personAudible
            || fact.predicate == WorldFacts.cameraWatching
            || (fact.predicate == WorldFacts.characterRegion && fact.subjectID == character)
    }

    private static func line(for fact: Fact, character: EntityID, now: Date, in timeZone: TimeZone)
        -> String?
    {
        guard !isUnspoken(fact, character: character) else { return nil }
        var parts = [
            "\(subjectName(of: fact.subjectID)) · \(fact.predicate) = \(rendered(fact.value))"
        ]
        var when =
            "since \(clock(fact.validFrom, in: timeZone)) (\(age(of: fact.validFrom, now: now).lowercased()))"
        if let until = fact.validTo {
            when += ", until \(clock(until, in: timeZone))"
        }
        parts.append(when)
        parts.append(basis(of: fact.epistemic))
        return parts.joined(separator: " · ")
    }

    /// "observed", "assumed (nobody has checked)", "reported", "inferred (70%)".
    static func basis(of epistemic: EpistemicState) -> String {
        var text =
            switch epistemic.type {
            case .observed: "observed"
            case .assumed: "assumed (nobody has checked)"
            case .reported: "reported"
            case .inferred: "inferred"
            case .scheduled: "scheduled"
            case .forecast: "forecast"
            case .remembered: "remembered"
            }
        if epistemic.confidence < 0.999 {
            text += " (\(Int((epistemic.confidence * 100).rounded()))% sure)"
        }
        return text
    }

    /// "The front door", "Mango", "April", "the house", "this room".
    static func subjectName(of entityID: EntityID) -> String {
        let raw = entityID.rawValue
        if raw.hasPrefix("place:") { return placeName(of: entityID) }
        if raw.hasPrefix("house:") { return "The house" }
        if raw.hasPrefix("region:") { return "This room" }
        return name(of: entityID)
    }

    /// A value as itself: `unlocked`, `"April's sister"`, `67.1`, `yes`, `none`,
    /// `[Normal Evening, Movie Time]`, or the lines of a scene as `Beaky: "…"; Kenny: "…"`.
    static func rendered(_ value: WorldJSONValue) -> String {
        switch value {
        case .string(let text):
            if let id = EntityID(rawValue: text), text.contains(":") { return subjectName(of: id) }
            return text.contains(" ") ? "\"\(text)\"" : text
        case .number(let number):
            return number == number.rounded() ? String(Int(number)) : String(format: "%.1f", number)
        case .bool(let flag): return flag ? "yes" : "no"
        case .null: return "none"
        case .array(let items): return "[" + items.map(rendered).joined(separator: ", ") + "]"
        case .object(let object):
            if case .array(let lines)? = object["lines"] {
                let spoken = lines.compactMap { line -> String? in
                    guard case .object(let entry) = line,
                        case .string(let who)? = entry["character_id"],
                        case .string(let text)? = entry["text"]
                    else { return nil }
                    let speaker = EntityID(rawValue: who).map(name(of:)) ?? who
                    return "\(speaker): \"\(text)\""
                }
                if !spoken.isEmpty { return spoken.joined(separator: "; ") }
            }
            return object.keys.sorted().map { "\($0)=\(rendered(object[$0]!))" }
                .joined(separator: ", ")
        }
    }

    static func clock(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return date.formatted(
            Date.FormatStyle(
                date: .omitted, time: .shortened, locale: calendar.locale!, calendar: calendar,
                timeZone: timeZone)
        )
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// "It is 11:58 PM on Thursday, September 11." — the local wall clock in words, so the
    /// model never converts a zone or guesses the day. Fixed to English and a Gregorian
    /// calendar: this is Beaky's sentence, not the host's locale.
    static func timeSentence(_ now: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let clock = now.formatted(
            Date.FormatStyle(
                date: .omitted, time: .shortened, locale: calendar.locale!,
                calendar: calendar, timeZone: timeZone))
        let day = now.formatted(
            Date.FormatStyle(locale: calendar.locale!, calendar: calendar, timeZone: timeZone)
                .weekday(.wide).month(.wide).day())
        // Foundation sets "11:58 PM" with a narrow no-break space; the prompt gets plain ones.
        return "It is \(clock) on \(day)."
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// "8:03:05 PM (5 minutes ago): The front door was just unlocked." — one line per
    /// happening, oldest first, so the mind reads the story in order. A happening the world
    /// has no sentence for is named by its kind and subject: "camera.person_seen at the carport".
    static func happeningLines(_ happenings: [Happening], now: Date, in timeZone: TimeZone)
        -> [String]
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let style = Date.FormatStyle(
            date: .omitted, time: .standard, locale: calendar.locale!, calendar: calendar,
            timeZone: timeZone)
        return happenings.map { happening in
            let clock = happening.occurredAt.formatted(style)
                .replacingOccurrences(of: "\u{202F}", with: " ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
            let what =
                happening.summary
                ?? "\(happening.type.rawValue) at \(placeName(of: happening.subjectID).lowercased())"
            return "\(clock) (\(age(of: happening.occurredAt, now: now).lowercased())): \(what)"
        }
    }

    /// The characters the facts place somewhere — logged in, not logged out (`null`).
    static func presentCharacters(in facts: [Fact]) -> [EntityID] {
        facts.filter { $0.predicate == WorldFacts.characterRegion && $0.value != .null }
            .map(\.subjectID)
    }

    static func name(of entityID: EntityID) -> String {
        let raw = entityID.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        return String(raw[raw.index(after: colon)...]).capitalized
    }

    /// `place:front-door` → "The front door"; `place:outside` → "Outside".
    static func placeName(of entityID: EntityID) -> String {
        let raw = entityID.rawValue
        let local = raw.firstIndex(of: ":").map { String(raw[raw.index(after: $0)...]) } ?? raw
        let words = local.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        let name = words.joined(separator: " ")
        let article: Set<String> = ["outside", "outdoors", "upstairs", "downstairs"]
        return article.contains(name) ? name.capitalized : "The " + name
    }

    /// "Mango (he/him)" when the world knows the pronouns, "Mango" when it does not.
    static func name(of entityID: EntityID, pronouns: String?) -> String {
        guard let pronouns, !pronouns.isEmpty else { return name(of: entityID) }
        return "\(name(of: entityID)) (\(pronouns))"
    }

    private static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Just now"
        case ..<3_600: return plural(Int(seconds / 60), "minute") + " ago"
        default: return plural(Int(seconds / 3_600), "hour") + " ago"
        }
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}

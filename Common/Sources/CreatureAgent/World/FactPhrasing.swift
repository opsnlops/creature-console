import Foundation
import WorldCore

/// Turns the world's facts into the plain sentences a character can think with. The model
/// never sees `presence.region`; it sees "Mango is here in the room with you".
enum FactPhrasing {
    /// The "What you know" lines for a character, newest fact first, skipping facts that have
    /// no phrasing yet rather than dumping them.
    static func lines(
        for facts: [Fact],
        character: EntityID,
        now: Date
    ) -> [String] {
        let pronouns = pronouns(in: facts)
        return facts.compactMap {
            sentence(for: $0, character: character, now: now, pronouns: pronouns)
        }
    }

    /// Who uses which pronouns, from `identity.pronouns` facts.
    static func pronouns(in facts: [Fact]) -> [EntityID: String] {
        var pronouns: [EntityID: String] = [:]
        for fact in facts where fact.predicate == WorldFacts.characterPronouns {
            if case .string(let value) = fact.value, pronouns[fact.subjectID] == nil {
                pronouns[fact.subjectID] = value
            }
        }
        return pronouns
    }

    static func sentence(
        for fact: Fact, character: EntityID, now: Date, pronouns: [EntityID: String] = [:]
    ) -> String? {
        let subject = name(of: fact.subjectID)
        let certainty = qualifier(for: fact.epistemic)
        switch fact.predicate {
        case WorldFacts.characterRegion:
            if fact.subjectID == character { return nil }  // Beaky knows where Beaky is.
            guard case .string = fact.value else {
                return "\(subject) has left."
            }
            let who = name(of: fact.subjectID, pronouns: pronouns[fact.subjectID])
            return "\(who) is here in the room with you\(certainty)."
        case WorldFacts.characterPronouns:
            return nil  // said alongside the name wherever the character is mentioned.
        case WorldFacts.personState:
            guard case .string(let state) = fact.value else { return nil }
            switch state {
            case "home": return "\(subject) is home\(certainty)."
            case "away": return "\(subject) is away\(certainty)."
            default: return nil
            }
        case "presence.physically_audible":
            return nil  // folded into the router's choice; not something to say.
        case WorldFacts.lastScene:
            guard case .object(let scene) = fact.value,
                case .array(let lines)? = scene["lines"], !lines.isEmpty
            else { return nil }
            let spoken = lines.compactMap { line -> String? in
                guard case .object(let entry) = line,
                    case .string(let who)? = entry["character_id"],
                    case .string(let text)? = entry["text"]
                else { return nil }
                return "\(name(of: EntityID(rawValue: who) ?? fact.subjectID)) said \"\(text)\""
            }
            guard !spoken.isEmpty else { return nil }
            return "\(age(of: fact.validFrom, now: now)), in this room: "
                + spoken.joined(separator: "; ") + "."
        default:
            // Unknown predicates stay out of the prompt; the Viewer shows them raw.
            return nil
        }
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

    /// "Mango (he/him)" when the world knows the pronouns, "Mango" when it does not.
    static func name(of entityID: EntityID, pronouns: String?) -> String {
        guard let pronouns, !pronouns.isEmpty else { return name(of: entityID) }
        return "\(name(of: entityID)) (\(pronouns))"
    }

    private static func qualifier(for epistemic: EpistemicState) -> String {
        switch epistemic.type {
        case .assumed: " (you assume; nobody has checked)"
        case .inferred where epistemic.confidence < 0.8: " (probably)"
        case .forecast: " (expected)"
        default: ""
        }
    }

    private static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Just now"
        case ..<3_600: return "\(Int(seconds / 60)) minutes ago"
        default: return "\(Int(seconds / 3_600)) hours ago"
        }
    }
}

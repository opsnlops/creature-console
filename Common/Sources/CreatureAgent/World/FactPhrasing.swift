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
        var lines = facts.compactMap {
            sentence(for: $0, character: character, now: now, pronouns: pronouns)
        }
        // A person the world can only describe in one phrase is a blank a small model fills
        // with invention ("Polly lives in Seattle"); say plainly that the blank is a blank.
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
        case WorldFacts.personDescription:
            guard case .string(let description) = fact.value else { return nil }
            return "\(subject) is \(description)."
        case WorldFacts.personState:
            guard case .string(let state) = fact.value else { return nil }
            switch state {
            case "home": return "\(subject) is home\(certainty)."
            case "away": return "\(subject) is away\(certainty)."
            default: return nil
            }
        case "presence.physically_audible":
            return nil  // folded into the router's choice; not something to say.
        case WorldFacts.doorLock:
            guard case .string(let state) = fact.value else { return nil }
            let place = placeName(of: fact.subjectID)
            return state == "unlocked"
                ? "\(place) was unlocked \(age(of: fact.validFrom, now: now).lowercased())."
                : "\(place) is locked."
        case WorldFacts.doorState:
            guard case .string(let state) = fact.value else { return nil }
            let place = placeName(of: fact.subjectID)
            return state == "open"
                ? "\(place) is open (opened \(age(of: fact.validFrom, now: now).lowercased()))."
                : "\(place) is closed."
        case WorldFacts.motionActive:
            guard case .bool(true) = fact.value else { return nil }
            return
                "Someone moved in \(placeName(of: fact.subjectID).lowercased()) \(age(of: fact.validFrom, now: now).lowercased())."
        case let predicate where predicate.hasPrefix(WorldFacts.seenPrefix):
            guard case .bool(true) = fact.value else { return nil }
            let what = String(predicate.dropFirst(WorldFacts.seenPrefix.count))
            let article = what == "animal" ? "An" : "A"
            let place = placeName(of: fact.subjectID)
            let at = place == place.capitalized ? place.lowercased() : "at " + place.lowercased()
            return
                "\(article) \(what) was seen \(at) \(age(of: fact.validFrom, now: now).lowercased())."
        case let predicate where predicate.hasPrefix(WorldFacts.environmentPrefix):
            return measurement(
                String(predicate.dropFirst(WorldFacts.environmentPrefix.count)), fact: fact)
        case WorldFacts.houseScenes:
            guard case .array(let names) = fact.value, !names.isEmpty else { return nil }
            let list = names.compactMap { value -> String? in
                if case .string(let name) = value { return name }
                return nil
            }
            return
                "The house can set the lights to these scenes: \(list.joined(separator: ", ")). You cannot set them yourself: the house acts when April names one, and you will be told here when it does. Never say the lights are changing unless you are told so below; if April asks and you were not told, say the house did not catch it and ask her to name the scene."
        case WorldFacts.houseSceneRequested:
            guard case .string(let scene) = fact.value else { return nil }
            return
                "April just asked for the lights to be set to \(scene), and the house is doing it right now."
        case WorldFacts.houseScene:
            guard case .string(let scene) = fact.value else { return nil }
            return
                "The lights are set to \(scene) (since \(age(of: fact.validFrom, now: now).lowercased()))."
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

    /// `place:front-door` → "The front door"; `place:outside` → "Outside".
    static func placeName(of entityID: EntityID) -> String {
        let raw = entityID.rawValue
        let local = raw.firstIndex(of: ":").map { String(raw[raw.index(after: $0)...]) } ?? raw
        let words = local.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        let name = words.joined(separator: " ")
        let article: Set<String> = ["outside", "outdoors", "upstairs", "downstairs"]
        return article.contains(name) ? name.capitalized : "The " + name
    }

    /// "It is 68 degrees outside." / "The humidity in the workshop is 41 percent."
    private static func measurement(_ predicate: String, fact: Fact) -> String? {
        guard case .number(let value) = fact.value else { return nil }
        let place = placeName(of: fact.subjectID)
        let rounded = value.rounded()
        let shown = rounded == value ? String(Int(rounded)) : String(format: "%.1f", value)
        switch predicate {
        case "temperature_f":
            return
                "It is \(shown) degrees \(place == place.capitalized ? place.lowercased() : "at " + place.lowercased())."
        case "temperature_c":
            return
                "It is \(shown) degrees Celsius \(place == place.capitalized ? place.lowercased() : "at " + place.lowercased())."
        case "humidity_percent":
            return
                "The humidity \(place == place.capitalized ? place.lowercased() : "at " + place.lowercased()) is \(shown) percent."
        default:
            return "\(place): \(predicate.replacingOccurrences(of: "_", with: " ")) is \(shown)."
        }
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
        case ..<3_600: return plural(Int(seconds / 60), "minute") + " ago"
        default: return plural(Int(seconds / 3_600), "hour") + " ago"
        }
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}

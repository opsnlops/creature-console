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
        facts.compactMap { sentence(for: $0, character: character, now: now) }
    }

    static func sentence(for fact: Fact, character: EntityID, now: Date) -> String? {
        let subject = name(of: fact.subjectID)
        let certainty = qualifier(for: fact.epistemic)
        switch fact.predicate {
        case "presence.region":
            if fact.subjectID == character { return nil }  // Beaky knows where Beaky is.
            guard case .string = fact.value else {
                return "\(subject) has left."
            }
            return "\(subject) is here in the room with you\(certainty)."
        case "presence.state":
            guard case .string(let state) = fact.value else { return nil }
            switch state {
            case "home": return "\(subject) is home\(certainty)."
            case "away": return "\(subject) is away\(certainty)."
            default: return nil
            }
        case "presence.physically_audible":
            return nil  // folded into the router's choice; not something to say.
        case "scene.last":
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

    static func name(of entityID: EntityID) -> String {
        let raw = entityID.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        return String(raw[raw.index(after: colon)...]).capitalized
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

import Foundation
import WorldCore

/// One calendar event, as plain values - EventKit's answer without EventKit's types.
struct CalendarItem: Equatable, Sendable, Codable {
    var identifier: String
    var calendar: String
    var title: String
    var location: String
    var notes: String
    var starts: Date
    var ends: Date
    var isAllDay: Bool
    /// Attendees as the calendar names them: email when it has one, else the display name.
    var attendees: [Attendee]

    struct Attendee: Equatable, Sendable, Codable {
        var name: String
        var email: String?
    }
}

/// Who an attendee, or a name in a title, is in the world: built from April's contact map, so
/// "Jesse Alvarez" and jesse@example.com both find `person:jesse`.
struct PersonResolver: Sendable {
    private var byEmail: [String: EntityID] = [:]
    private var byName: [String: EntityID] = [:]
    private var byFirstName: [String: EntityID] = [:]

    init(cards: [ContactCard], map: [String: ContactMapping]) {
        for (identifier, mapping) in map {
            guard let card = cards.first(where: { $0.identifier == identifier }) else { continue }
            for email in card.emails.values {
                byEmail[email.lowercased()] = mapping.entityID
            }
            if !card.fullName.isEmpty { byName[card.fullName.lowercased()] = mapping.entityID }
            if !card.nickname.isEmpty { byName[card.nickname.lowercased()] = mapping.entityID }
            if !card.givenName.isEmpty {
                // A first name shared by two mapped people names neither.
                let first = card.givenName.lowercased()
                byFirstName[first] = byFirstName[first] == nil ? mapping.entityID : nil
            }
        }
    }

    func person(email: String?, name: String?) -> EntityID? {
        if let email, let id = byEmail[email.lowercased()] { return id }
        if let name, let id = byName[name.lowercased()] { return id }
        return nil
    }

    /// The first mapped person whose first name is a word of the title: "Jesse - deck boards".
    func person(inTitle title: String) -> EntityID? {
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.lazy.compactMap { byFirstName[$0] ?? nil }.first
    }

    /// April's own word in the event's notes, which beats every guess: a line "Beaky: person:jesse"
    /// says who it is with; "Beaky: nobody" says the guess is wrong and there is no one.
    enum Word: Equatable {
        case person(EntityID)
        case nobody
    }

    static func word(inNotes notes: String) -> Word? {
        for line in notes.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":"),
                trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    == ContactMapping.label.lowercased()
            else { continue }
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces).lowercased()
            if ["nobody", "none", "no one", "no-one"].contains(value) { return .nobody }
            if value.hasPrefix("person:"), let id = EntityID(rawValue: value) { return .person(id) }
        }
        return nil
    }
}

/// The facts an event makes, on `event:<id>`. The world's own rule turns an event at the house
/// with a person into `visitor.expected`; the Bridge only says what the calendar says.
enum CalendarFacts {
    static let worldOnly: Set<String> = ["calendar.starts_at", "calendar.ends_at"]

    static let meanings: [String: String] = [
        "calendar.title": "what the calendar event is called",
        "calendar.when":
            "when the event is, in human terms (\"Thursday, September 18 at 2:00 PM\")",
        "calendar.starts_at": "when the event starts, as a timestamp - for the world's rules",
        "calendar.ends_at": "when the event ends, as a timestamp - for the world's rules",
        "calendar.location": "where the event is, as the calendar has it",
        "calendar.with":
            "the person the event is with - April's own word in the event's notes, or an attendee or name the calendar gives that April knows",
        "calendar.calendar": "which of April's calendars the event is on",
        "calendar.all_day": "whether the event is an all-day one",
    ]

    /// Facts for one event, valid until 90 days after it ends so "when was Jesse last here?"
    /// has an answer, then gone.
    static func facts(from item: CalendarItem, resolver: PersonResolver, zone: TimeZone)
        -> FactLedger.Wanted
    {
        var facts: [String: WorldJSONValue] = [
            "calendar.title": .string(item.title),
            "calendar.when": .string(when(item, zone: zone)),
            "calendar.starts_at": .string(WorldJSON.timestamp(item.starts)),
            "calendar.ends_at": .string(WorldJSON.timestamp(item.ends)),
            "calendar.calendar": .string(item.calendar),
        ]
        if item.isAllDay { facts["calendar.all_day"] = .bool(true) }
        if !item.location.isEmpty { facts["calendar.location"] = .string(item.location) }
        let with: EntityID?
        switch PersonResolver.word(inNotes: item.notes) {
        case .person(let id): with = id
        case .nobody: with = nil
        case nil:
            with =
                item.attendees.lazy.compactMap { resolver.person(email: $0.email, name: $0.name) }
                .first ?? resolver.person(inTitle: item.title)
        }
        if let with { facts["calendar.with"] = .string(with.rawValue) }
        return FactLedger.Wanted(
            entityID: entityID(for: item), facts: facts,
            validUntil: item.ends.addingTimeInterval(90 * 86_400))
    }

    /// `event:<calendar item id>-<day>`: a recurring event is one entity per occurrence.
    static func entityID(for item: CalendarItem) -> EntityID {
        let base = item.identifier.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        let slug = base.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: item.starts)
        return EntityID(rawValue: "event:\(slug.isEmpty ? "unnamed" : slug)-\(day)")!
    }

    /// "Thursday, September 18 at 2:00 PM" or "Thursday, September 18 (all day)".
    static func when(_ item: CalendarItem, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if item.isAllDay {
            formatter.dateFormat = "EEEE, MMMM d"
            return "\(formatter.string(from: item.starts)) (all day)"
        }
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return formatter.string(from: item.starts)
    }
}

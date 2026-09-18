import Foundation
import WorldCore

/// One reminder, as plain values - EventKit's answer without EventKit's types.
struct ReminderItem: Equatable, Sendable, Codable {
    var identifier: String
    var list: String
    var title: String
    var notes: String
    /// When it is due, if it has a day at all; `dueHasTime` says whether a clock time too.
    var due: Date?
    var dueHasTime: Bool
    /// EventKit's 0 (none), 1 (high) … 9 (low).
    var priority: Int
    var isCompleted: Bool
    var completedAt: Date?
}

/// The facts a reminder makes, on `reminder:<id>`: what April means to do, by when, and
/// whether she has. Only what is due soon rides in a mind's envelope (the world decides that);
/// the rest is there for the tools. The world's own rule nudges her when one falls due.
enum ReminderFacts {
    static let worldOnly: Set<String> = ["reminder.due_at", "reminder.completed_at"]

    static let meanings: [String: String] = [
        "reminder.title": "what April means to do, as she wrote it in Reminders",
        "reminder.due":
            "when it is due, in human terms (\"Friday, September 18 at 9:00 AM\", or a day); a due date already past is overdue, not done",
        "reminder.due_at": "when it is due, as a timestamp - for the world's rules",
        "reminder.list": "which of April's reminder lists it is on",
        "reminder.priority": "how important April marked it: high, medium, or low",
        "reminder.completed": "whether April has done it",
        "reminder.all_day": "whether it is due on a day rather than at a time",
        "reminder.completed_at": "when she marked it done, as a timestamp - for the world's rules",
        "reminder.for":
            "the person the reminder concerns - April's own word in its notes (a line \"Beaky: person:jesse\")",
    ]

    /// How long a done reminder stays, so "did I call the vet?" has an answer for a while.
    static let doneLingers: TimeInterval = 2 * 86_400
    /// How long past its due date an undone reminder is still cast; after that it is
    /// abandoned, not overdue, and the world lets it go.
    static let overdueLingers: TimeInterval = 14 * 86_400

    static func facts(from item: ReminderItem, zone: TimeZone) -> FactLedger.Wanted {
        var facts: [String: WorldJSONValue] = [
            "reminder.title": .string(item.title),
            "reminder.list": .string(item.list),
            "reminder.completed": .bool(item.isCompleted),
        ]
        if let due = item.due {
            facts["reminder.due"] = .string(when(due, hasTime: item.dueHasTime, zone: zone))
            facts["reminder.due_at"] = .string(WorldJSON.timestamp(due))
            if !item.dueHasTime { facts["reminder.all_day"] = .bool(true) }
        }
        if let priority = priorityWord(item.priority) {
            facts["reminder.priority"] = .string(priority)
        }
        if let completedAt = item.completedAt {
            facts["reminder.completed_at"] = .string(WorldJSON.timestamp(completedAt))
        }
        if case .person(let id)? = PersonResolver.word(inNotes: item.notes) {
            facts["reminder.for"] = .string(id.rawValue)
        }
        let validUntil: Date?
        if item.isCompleted {
            validUntil = (item.completedAt ?? Date()).addingTimeInterval(doneLingers)
        } else if let due = item.due {
            validUntil = due.addingTimeInterval(overdueLingers)
        } else {
            validUntil = nil
        }
        return FactLedger.Wanted(
            entityID: entityID(for: item), facts: facts, validUntil: validUntil)
    }

    static func entityID(for item: ReminderItem) -> EntityID {
        let slug = item.identifier.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return EntityID(rawValue: "reminder:\(slug.isEmpty ? "unnamed" : slug)")!
    }

    /// EventKit's 1–4 is high, 5 medium, 6–9 low, 0 none.
    static func priorityWord(_ priority: Int) -> String? {
        switch priority {
        case 1...4: "high"
        case 5: "medium"
        case 6...9: "low"
        default: nil
        }
    }

    /// "Friday, September 18 at 9:00 AM" or "Friday, September 18".
    static func when(_ due: Date, hasTime: Bool, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = hasTime ? "EEEE, MMMM d 'at' h:mm a" : "EEEE, MMMM d"
        return formatter.string(from: due)
    }
}

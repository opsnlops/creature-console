import Foundation
import WorldCore

/// `reminders` in world.json: when a reminder that is due gets a word.
struct ReminderRuleConfiguration: Codable, Equatable, Sendable {
    /// A reminder due on a day rather than at a time is due at this hour, local.
    var allDayHour: Int = 9
    /// How long after it falls due a reminder is still worth a word; past that it is
    /// yesterday's news, and a world that restarts a day later says nothing.
    var nudgeWindowMinutes: Int = 120

    init(allDayHour: Int = 9, nudgeWindowMinutes: Int = 120) {
        self.allDayHour = allDayHour
        self.nudgeWindowMinutes = nudgeWindowMinutes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allDayHour = try container.decodeIfPresent(Int.self, forKey: .allDayHour) ?? 9
        nudgeWindowMinutes =
            try container.decodeIfPresent(Int.self, forKey: .nudgeWindowMinutes) ?? 120
    }

    private enum CodingKeys: String, CodingKey {
        case allDayHour = "all_day_hour"
        case nudgeWindowMinutes = "nudge_window_minutes"
    }
}

/// A reminder falling due while April is home is the house's own occasion - "you've got
/// 'call the vet' due today and it's four o'clock" - said once, and then let be. The Bridge
/// casts what she means to do and by when; this rule watches the clock. What the birds say,
/// and whether, is theirs.
actor ReminderRule {
    static let sourceID = try! SourceID(validating: "world:reminders")

    struct Due: Equatable, Sendable {
        var reminder: EntityID
        var title: String
        var list: String
        var dueAt: Date
        var allDay: Bool
    }

    let configuration: ReminderRuleConfiguration
    let house: EntityID
    let zone: TimeZone
    private let facts: FactRepository
    private let accept: @Sendable (WorldEventEnvelope) async throws -> Void
    /// Said once per reminder per due time; a reminder rescheduled is new.
    private var said: Set<String> = []

    init(
        configuration: ReminderRuleConfiguration, house: EntityID, zone: TimeZone,
        facts: FactRepository, accept: @escaping @Sendable (WorldEventEnvelope) async throws -> Void
    ) {
        self.configuration = configuration
        self.house = house
        self.zone = zone
        self.facts = facts
        self.accept = accept
    }

    /// One pass. Returns the reminders that were due within the window, nudged or not.
    @discardableResult
    func sweep(now: Date) async throws -> [Due] {
        let dueFacts = try await facts.currentFacts(
            about: [], predicate: "reminder.due_at", limit: 500, at: now)
        let window = TimeInterval(configuration.nudgeWindowMinutes) * 60
        var due: [Due] = []
        for fact in dueFacts {
            guard case .string(let raw) = fact.value, var dueAt = WorldJSON.date(from: raw) else {
                continue
            }
            let reminder = try await facts.currentFacts(subjectID: fact.subjectID, at: now)
            func text(_ predicate: String) -> String? {
                if case .string(let value)? = reminder.first(where: { $0.predicate == predicate })?
                    .value
                {
                    return value
                }
                return nil
            }
            guard
                reminder.first(where: { $0.predicate == "reminder.completed" })?.value
                    != .bool(true)
            else { continue }
            let allDay =
                reminder.first(where: { $0.predicate == "reminder.all_day" })?.value == .bool(true)
            if allDay { dueAt = Self.atHour(configuration.allDayHour, of: dueAt, zone: zone) }
            guard dueAt <= now, now <= dueAt.addingTimeInterval(window) else { continue }
            due.append(
                Due(
                    reminder: fact.subjectID, title: text("reminder.title") ?? "a reminder",
                    list: text("reminder.list") ?? "", dueAt: dueAt, allDay: allDay))
        }
        for item in due {
            let key = "\(item.reminder.rawValue):\(WorldJSON.timestamp(item.dueAt))"
            guard !said.contains(key) else { continue }
            said.insert(key)
            guard try await aprilIsHome(now: now) else { continue }
            try await accept(try occasion(item, now: now))
        }
        return due
    }

    private func aprilIsHome(now: Date) async throws -> Bool {
        let april = try EntityID(validating: "person:april")
        let state = try await facts.currentFacts(subjectID: april, at: now)
            .first { $0.predicate == WorldFacts.personState }
        guard case .string(let value)? = state?.value else { return false }
        return value == PersonPresenceState.home.rawValue
    }

    /// The same local day at `hour`: an all-day reminder's real due time.
    static func atHour(_ hour: Int, of date: Date, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    /// `reminder.due`: the house's occasion. The scene openers make it a house
    /// consideration, once, while April is home.
    private func occasion(_ item: Due, now: Date) throws -> WorldEventEnvelope {
        let when =
            item.allDay ? "today" : "at \(DepartureRule.clock(item.dueAt, zone: zone))"
        return try WorldEventEnvelope(
            type: HouseEvents.reminderDue,
            occurredAt: now,
            source: EventSource(
                id: Self.sourceID, kind: "world",
                sourceEventID:
                    "reminder:\(item.reminder.rawValue):\(WorldJSON.timestamp(item.dueAt))"),
            subjectIDs: [house, item.reminder],
            placeID: house,
            epistemic: EpistemicState(type: .scheduled, confidence: 1),
            payload: [
                "reminder_id": .string(item.reminder.rawValue),
                "title": .string(item.title),
                "list": .string(item.list),
                "due_at": .string(WorldJSON.timestamp(item.dueAt)),
                "value": .string("\(item.title), due \(when)"),
            ])
    }
}

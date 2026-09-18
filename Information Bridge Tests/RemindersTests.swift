import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("Reminders as facts")
struct RemindersTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    @Test("A reminder is what to do, by when, and whether it is done; a day without a time says so")
    func remindersBecomeFacts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let due = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 18, hour: 16, minute: 0))!
        let timed = ReminderItem(
            identifier: "3B2A-VET", list: "Home", title: "Call the vet",
            notes: "Beaky: person:polly\nabout the cat", due: due, dueHasTime: true, priority: 1,
            isCompleted: false, completedAt: nil)
        let wanted = ReminderFacts.facts(from: timed, zone: zone)
        #expect(wanted.entityID.rawValue == "reminder:3b2a-vet")
        #expect(wanted.facts["reminder.title"] == .string("Call the vet"))
        #expect(wanted.facts["reminder.due"] == .string("Friday, September 18 at 4:00 PM"))
        #expect(wanted.facts["reminder.due_at"] == .string(WorldJSON.timestamp(due)))
        #expect(wanted.facts["reminder.all_day"] == nil)
        #expect(wanted.facts["reminder.priority"] == .string("high"))
        #expect(wanted.facts["reminder.completed"] == .bool(false))
        #expect(wanted.facts["reminder.for"] == .string("person:polly"))
        // Undone and dated: kept a fortnight past due, then let go.
        #expect(wanted.validUntil == due.addingTimeInterval(ReminderFacts.overdueLingers))

        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let allDay = ReminderItem(
            identifier: "BINS", list: "Home", title: "Bins out", notes: "", due: day,
            dueHasTime: false, priority: 0, isCompleted: false, completedAt: nil)
        let bins = ReminderFacts.facts(from: allDay, zone: zone)
        #expect(bins.facts["reminder.due"] == .string("Friday, September 18"))
        #expect(bins.facts["reminder.all_day"] == .bool(true))
        #expect(bins.facts["reminder.priority"] == nil)

        let doneAt = due.addingTimeInterval(600)
        let done = ReminderItem(
            identifier: "PLANTS", list: "Home", title: "Water plants", notes: "", due: nil,
            dueHasTime: false, priority: 9, isCompleted: true, completedAt: doneAt)
        let plants = ReminderFacts.facts(from: done, zone: zone)
        #expect(plants.facts["reminder.completed"] == .bool(true))
        #expect(plants.facts["reminder.completed_at"] == .string(WorldJSON.timestamp(doneAt)))
        #expect(plants.facts["reminder.due"] == nil)
        #expect(plants.facts["reminder.priority"] == .string("low"))
        #expect(plants.validUntil == doneAt.addingTimeInterval(ReminderFacts.doneLingers))
        // No date, not done: kept until it goes.
        let open = ReminderItem(
            identifier: "SOMEDAY", list: "Home", title: "Learn the ukulele", notes: "", due: nil,
            dueHasTime: false, priority: 0, isCompleted: false, completedAt: nil)
        #expect(ReminderFacts.facts(from: open, zone: zone).validUntil == nil)
        #expect(ReminderFacts.worldOnly == ["reminder.due_at", "reminder.completed_at"])
    }

    @Test("The source casts what changed and takes back what is gone")
    func sourceReconciles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reminders-\(UUID().uuidString)")
        let casts = Casts()
        let listed = Listed()
        let source = RemindersSource(
            directory: directory, zone: zone,
            read: { _ in await listed.items },
            cast: { await casts.note($0) })
        await listed.set([
            ReminderItem(
                identifier: "VET", list: "Home", title: "Call the vet", notes: "", due: nil,
                dueHasTime: false, priority: 0, isCompleted: false, completedAt: nil)
        ])
        await source.poll(now: Date(timeIntervalSince1970: 1_789_700_000))
        var events = await casts.events
        #expect(
            Set(events.map { $0.payload["predicate"]?.stringValue ?? "" })
                == ["reminder.title", "reminder.list", "reminder.completed"])
        #expect(events.allSatisfy { $0.payload["subject_id"] == .string("reminder:vet") })
        // Deleted in Reminders: every fact taken back.
        await listed.set([])
        await source.poll(now: Date(timeIntervalSince1970: 1_789_700_060))
        events = await casts.events
        #expect(events.count == 6)
        #expect(events.suffix(3).allSatisfy { $0.payload["value"] == .null })
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

private actor Listed {
    private(set) var items: [ReminderItem] = []
    func set(_ items: [ReminderItem]) { self.items = items }
}

extension WorldJSONValue {
    fileprivate var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}

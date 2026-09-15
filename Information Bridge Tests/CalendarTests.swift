import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("The calendar, as facts")
struct CalendarTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    private let jesse = try! EntityID(validating: "person:jesse")
    // 2026-09-17 14:00 PDT
    private let thursday = Date(timeIntervalSince1970: 1_789_678_800)

    private var resolver: PersonResolver {
        PersonResolver(
            cards: [
                ContactCard(
                    identifier: "card-jesse", givenName: "Jesse", familyName: "Alvarez",
                    nickname: "", organization: "", jobTitle: "", phones: [:],
                    emails: ["work": "jesse@example.com"], addresses: [:], birthday: nil,
                    relations: [:])
            ],
            map: ["card-jesse": ContactMapping(entityID: jesse)])
    }

    private func item(
        _ title: String, attendees: [CalendarItem.Attendee] = [], location: String = "",
        allDay: Bool = false
    ) -> CalendarItem {
        CalendarItem(
            identifier: "ABC-123:2026-09-17T21:00:00Z", calendar: "Home", title: title,
            location: location, notes: "private notes never leave", starts: thursday,
            ends: thursday.addingTimeInterval(7_200), isAllDay: allDay, attendees: attendees)
    }

    @Test("An event becomes facts in human words, with the person found by attendee or title")
    func eventBecomesFacts() {
        let byAttendee = CalendarFacts.facts(
            from: item(
                "Deck boards", attendees: [.init(name: "J. Alvarez", email: "jesse@example.com")],
                location: "Home"),
            resolver: resolver, zone: pacific)
        #expect(byAttendee.entityID.rawValue == "event:abc-123-20260917")
        #expect(byAttendee.facts["calendar.title"] == .string("Deck boards"))
        #expect(byAttendee.facts["calendar.when"] == .string("Thursday, September 17 at 2:00 PM"))
        #expect(byAttendee.facts["calendar.with"] == .string("person:jesse"))
        #expect(byAttendee.facts["calendar.location"] == .string("Home"))
        #expect(byAttendee.facts["calendar.starts_at"] == .string("2026-09-17T21:00:00.000Z"))
        #expect(byAttendee.facts["calendar.all_day"] == nil)
        #expect(byAttendee.facts.values.contains(.string("private notes never leave")) == false)
        // Held for 90 days after it ends, so "when was Jesse last here?" has an answer.
        #expect(byAttendee.validUntil == thursday.addingTimeInterval(7_200 + 90 * 86_400))

        let byTitle = CalendarFacts.facts(
            from: item("Jesse - deck boards 2pm"), resolver: resolver, zone: pacific)
        #expect(byTitle.facts["calendar.with"] == .string("person:jesse"))

        let nobody = CalendarFacts.facts(
            from: item("Dentist", allDay: true), resolver: resolver, zone: pacific)
        #expect(nobody.facts["calendar.with"] == nil)

        // April's own word in the notes beats the guess, either way.
        var told = item("Dentist")
        told.notes = "bring the forms\nBeaky: person:jesse"
        #expect(
            CalendarFacts.facts(from: told, resolver: resolver, zone: pacific)
                .facts["calendar.with"] == .string("person:jesse"))
        var notJesse = item("Jesse - deck boards")
        notJesse.notes = "beaky: nobody"
        #expect(
            CalendarFacts.facts(from: notJesse, resolver: resolver, zone: pacific)
                .facts["calendar.with"] == nil)
        #expect(nobody.facts["calendar.when"] == .string("Thursday, September 17 (all day)"))
        #expect(nobody.facts["calendar.all_day"] == .bool(true))
        #expect(CalendarFacts.worldOnly == ["calendar.starts_at", "calendar.ends_at"])
    }

    @Test("A cancelled event is taken back; a rescheduled one re-cast")
    func cancelledAndRescheduled() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "calendar-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let casts = Casts()
        let book = Agenda(items: [item("Deck boards", location: "Home")])
        let resolver = self.resolver
        let source = CalendarSource(
            directory: directory, zone: pacific, allowed: nil,
            read: { _, _, _ in await book.items }, resolver: { resolver }
        ) { await casts.note($0) }
        await source.poll(now: thursday.addingTimeInterval(-86_400))
        let first = await casts.events.count
        #expect(first == 6)
        #expect(
            await casts.events.allSatisfy {
                $0.subjectIDs.first?.rawValue == "event:abc-123-20260917"
            })
        #expect(await casts.events.allSatisfy { $0.payload["valid_to"] != nil })

        var later = item("Deck boards", location: "Home")
        later.starts = thursday.addingTimeInterval(3_600)
        later.ends = later.starts.addingTimeInterval(7_200)
        await book.replace([later])
        await source.poll(now: thursday.addingTimeInterval(-80_000))
        let changed = await casts.events.dropFirst(first)
        #expect(
            Set(
                changed.compactMap {
                    if case .string(let p)? = $0.payload["predicate"] { p } else { nil }
                })
                == ["calendar.when", "calendar.starts_at", "calendar.ends_at"])

        await book.replace([])
        await source.poll(now: thursday.addingTimeInterval(-70_000))
        let gone = await casts.events.dropFirst(first + changed.count)
        #expect(gone.count == 6)
        #expect(gone.allSatisfy { $0.payload["value"] == .null })
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

private actor Agenda {
    private(set) var items: [CalendarItem]
    init(items: [CalendarItem]) { self.items = items }
    func replace(_ items: [CalendarItem]) { self.items = items }
}

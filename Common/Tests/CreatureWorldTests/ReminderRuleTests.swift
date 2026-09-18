import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

@Suite(
    "The reminders' rule",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct ReminderRuleTests {
    @Test(
        "A reminder falling due with April home is the house's occasion, once; done, all-day, and away are not"
    )
    func remindersAreOccasions() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "reminder-rule-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // Ten past three in the afternoon, local, today.
        let now = calendar.date(bySettingHour: 15, minute: 10, second: 0, of: Date())!
        let house = try EntityID(validating: "house:reminders-\(suffix)")
        let vet = try EntityID(validating: "reminder:vet-\(suffix)")
        let bins = try EntityID(validating: "reminder:bins-\(suffix)")
        let done = try EntityID(validating: "reminder:done-\(suffix)")
        let later = try EntityID(validating: "reminder:later-\(suffix)")
        let april = try EntityID(validating: "person:april")
        func fact(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue) throws -> Fact
        {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: now.addingTimeInterval(-3_600), validTo: now.addingTimeInterval(86_400),
                derivedFrom: [],
                producer: FactProducer(kind: "bridge", id: "reminders", version: "1"))
        }
        // Earlier runs left reminders due at this same time of day in the shared database;
        // they are ended first, or the rule counts them as this run's.
        for leftover in try await persistence.facts.currentFacts(
            about: [], predicate: "reminder.due_at", limit: 500, at: now)
        {
            try await persistence.facts.supersede(
                by: try Fact(
                    subjectID: leftover.subjectID, predicate: leftover.predicate, value: .null,
                    epistemic: EpistemicState(type: .reported, confidence: 1),
                    validFrom: now.addingTimeInterval(-2), validTo: now.addingTimeInterval(-1),
                    derivedFrom: [],
                    producer: FactProducer(kind: "test", id: "cleanup", version: "1")))
        }
        let vetDue = now.addingTimeInterval(-10 * 60)
        for f in [
            try fact(vet, "reminder.title", .string("Call the vet \(suffix)")),
            try fact(vet, "reminder.due_at", .string(WorldJSON.timestamp(vetDue))),
            try fact(vet, "reminder.completed", .bool(false)),
            // Due today, no time: due at the configured hour (9), long past the window by now.
            try fact(bins, "reminder.title", .string("Bins out")),
            try fact(
                bins, "reminder.due_at", .string(WorldJSON.timestamp(calendar.startOfDay(for: now)))
            ),
            try fact(bins, "reminder.all_day", .bool(true)),
            try fact(bins, "reminder.completed", .bool(false)),
            // Done already.
            try fact(done, "reminder.title", .string("Water plants")),
            try fact(
                done, "reminder.due_at", .string(WorldJSON.timestamp(now.addingTimeInterval(-60)))),
            try fact(done, "reminder.completed", .bool(true)),
            // Not yet.
            try fact(later, "reminder.title", .string("Dinner prep")),
            try fact(
                later, "reminder.due_at",
                .string(WorldJSON.timestamp(now.addingTimeInterval(3_600)))),
            try fact(later, "reminder.completed", .bool(false)),
        ] {
            try await persistence.facts.save(f)
        }
        try await persistence.facts.save(
            try Fact(
                subjectID: april, predicate: WorldFacts.personState, value: .string("home"),
                epistemic: EpistemicState(type: .observed, confidence: 1), validFrom: now,
                validTo: now.addingTimeInterval(3 * 3_600), derivedFrom: [],
                producer: FactProducer(kind: "house", id: "test-\(suffix)", version: "1")))
        let accepted = Accepted()
        let rule = ReminderRule(
            configuration: ReminderRuleConfiguration(allDayHour: 9, nudgeWindowMinutes: 120),
            house: house, zone: zone, facts: persistence.facts
        ) { await accepted.note($0) }
        func mine() async -> [WorldEventEnvelope] {
            await accepted.events.filter { $0.subjectIDs.contains(house) }
        }

        let due = try await rule.sweep(now: now)
        // Only the vet is due within the window: the bins were due at nine, the plants are
        // done, dinner is later.
        #expect(due.map(\.reminder) == [vet])
        var events = await mine()
        #expect(events.count == 1)
        #expect(events[0].type == HouseEvents.reminderDue)
        #expect(events[0].payload["title"] == .string("Call the vet \(suffix)"))
        #expect(events[0].payload["value"]?.stringValue?.hasPrefix("Call the vet") == true)
        #expect(events[0].payload["value"]?.stringValue?.contains("due at 3:00 PM") == true)
        #expect(
            SceneOpeningPolicy.triggerText(for: events[0], place: house).hasPrefix(
                "A reminder of April's is due: Call the vet"))

        // Said once.
        _ = try await rule.sweep(now: now.addingTimeInterval(60))
        events = await mine()
        #expect(events.count == 1)

        // The all-day one, at nine that morning, with April home: an occasion then.
        let nine = calendar.date(bySettingHour: 9, minute: 5, second: 0, of: now)!
        try await persistence.facts.save(
            try Fact(
                subjectID: april, predicate: WorldFacts.personState, value: .string("home"),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: nine.addingTimeInterval(-60), validTo: now.addingTimeInterval(86_400),
                derivedFrom: [],
                producer: FactProducer(kind: "house", id: "test-\(suffix)", version: "1")))
        let morning = try await rule.sweep(now: nine)
        #expect(morning.map(\.reminder) == [bins])
        #expect(await mine().last?.payload["value"] == .string("Bins out, due today"))
    }
}

private actor Accepted {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

extension WorldJSONValue {
    fileprivate var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}

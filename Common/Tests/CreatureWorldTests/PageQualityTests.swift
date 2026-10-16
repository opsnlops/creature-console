import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// #231: the thirty facts a mind is handed are what is worth reading; the stage and the state
/// ride beside them, the state folded.
@Suite("The page: folding the state")
struct PageFoldingTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let outside = try! EntityID(validating: "place:outside")
    private let house = try! EntityID(validating: "house:aprils-nest")

    private func reading(
        _ subject: EntityID, _ predicate: String, _ value: WorldJSONValue, minutesAgo: Double = 0,
        type: EpistemicType = .observed, validTo: Date? = nil
    ) throws -> Fact {
        try Fact(
            subjectID: subject, predicate: predicate, value: value,
            epistemic: EpistemicState(type: type, confidence: 1),
            validFrom: now.addingTimeInterval(-minutesAgo * 60), validTo: validTo,
            derivedFrom: [], producer: FactProducer(kind: "house", id: "house", version: "1"))
    }

    @Test("A place's readings are one entry, in their units, the light's trend beside the light")
    func readingsFoldIntoOne() throws {
        let readings = [
            try reading(outside, "environment.pressure_hpa", .number(1010.28686523438)),
            try reading(outside, "environment.humidity_percent", .number(89), minutesAgo: 7),
            try reading(outside, "environment.light_lux", .number(120), minutesAgo: 3),
            try reading(outside, "environment.light_trend", .string("dimming"), minutesAgo: 3),
            try reading(outside, "environment.temperature_f", .number(51.7), minutesAgo: 12),
            try reading(outside, "environment.wind_mph", .number(0), minutesAgo: 30),
            try reading(outside, "environment.pm25_ugm3", .number(2.65000009536743)),
            try reading(house, "environment.power_w", .number(1966.083)),
        ]
        let folded = PageFolding.fold(readings)
        #expect(folded.count == 2)
        let air = try #require(folded.first { $0.subjectID == outside })
        #expect(air.predicate == WorldFacts.environmentNow)
        #expect(
            air.value
                == .string(
                    "temperature 51.7°F, humidity 89%, light 120 lux, dimming, wind 0 mph, PM2.5 2.7 µg/m³, pressure 1010.3 hPa"
                ))
        // As new as its newest reading; Why? walks to every one of them.
        #expect(air.validFrom == now)
        #expect(air.derivedFrom.count == 7)
        #expect(air.producer.id == "page")
        let power = try #require(folded.first { $0.subjectID == house })
        #expect(power.value == .string("power 1966.1 W"))
    }

    @Test("Without the light reading, the trend still says which way the light is going")
    func trendAlone() throws {
        let folded = PageFolding.fold([
            try reading(outside, "environment.light_trend", .string("brightening")),
            try reading(outside, "environment.temperature_f", .number(40)),
        ])
        #expect(folded.first?.value == .string("temperature 40°F, light brightening"))
    }

    @Test("The forecasts are one outlook in their own words; numbers only where no words say them")
    func forecastsFoldIntoAnOutlook() throws {
        let tomorrowEnds = now.addingTimeInterval(86_400)
        let tonightEnds = now.addingTimeInterval(3 * 3_600)
        let folded = PageFolding.fold([
            try reading(
                outside, "forecast.tomorrow", .string("Partly Cloudy, high 70°, low 50°"),
                type: .forecast, validTo: tomorrowEnds),
            try reading(
                outside, "forecast.tomorrow.high_f", .number(70), type: .forecast,
                validTo: tomorrowEnds),
            try reading(
                outside, "forecast.tomorrow.low_f", .number(50), type: .forecast,
                validTo: tomorrowEnds),
            try reading(
                outside, "forecast.tonight", .string("Mostly Clear"), type: .forecast,
                validTo: tonightEnds),
            try reading(
                outside, "forecast.today.high_f", .number(64), type: .forecast,
                validTo: tonightEnds),
        ])
        let outlook = try #require(folded.first)
        #expect(outlook.predicate == WorldFacts.forecastOutlook)
        #expect(
            outlook.value
                == .string(
                    "today: high 64°; tonight: Mostly Clear; tomorrow: Partly Cloudy, high 70°, low 50°"
                ))
        // It lasts as long as its shortest part, and it is a forecast, not an observation.
        #expect(outlook.validTo == tonightEnds)
        #expect(outlook.epistemic.type == .forecast)
    }

    @Test("An ended reading folds into nothing; other families are not the fold's")
    func onlyCurrentFoldedFamilies() throws {
        #expect(
            PageFolding.fold([
                try reading(outside, "environment.temperature_f", .null),
                try reading(outside, "door.lock", .string("locked")),
            ]).isEmpty)
    }

    @Test("The folded families are matched by prefix, every one of them")
    func prefixPattern() throws {
        let pattern = FactRepository.prefixPattern(["memory.", "environment."])
        #expect(pattern == #"^(?:memory\.|environment\.)"#)
        let regex = try NSRegularExpression(
            pattern: FactRepository.prefixPattern(WorldKnowledgeLimits.foldedPrefixes))
        func matches(_ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        #expect(matches("environment.light_trend"))
        #expect(matches("forecast.tomorrow.high_f"))
        #expect(!matches("door.lock"))
        #expect(!matches("my.environment.note"))
    }
}

@Suite(
    "The page, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct PageQualityMongoTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    @Test(
        "Sensors, forecasts, pronouns and rooms ride beside the thirty; learned facts fill them")
    func learnedFactsWinTheThirty() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "page-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let outside = try EntityID(validating: "place:outside-\(suffix)")
        let mango = try EntityID(validating: "character:mango-\(suffix)")
        func save(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue, _ ago: Double)
            async throws
        {
            try await persistence.facts.save(
                try Fact(
                    subjectID: subject, predicate: predicate, value: value,
                    epistemic: EpistemicState(type: .reported, confidence: 1),
                    validFrom: now.addingTimeInterval(-ago), derivedFrom: [],
                    producer: FactProducer(kind: "presence", id: "given-facts", version: "1")))
        }
        // Thirty-five things April taught them, all a day old...
        for index in 0..<35 {
            try await save(april, "taught.thing_\(index)", .string("thing \(index)"), 86_400)
        }
        // ...and the newest facts are the state, as every night: sensors, forecasts, the stage.
        for (index, sensor) in [
            "temperature_f", "humidity_percent", "light_lux", "wind_mph", "pm25_ugm3",
            "pressure_hpa",
        ].enumerated() {
            try await save(outside, "environment.\(sensor)", .number(Double(index)), 10)
        }
        try await save(outside, "environment.light_trend", .string("dimming"), 10)
        try await save(outside, "forecast.tonight", .string("Mostly Clear"), 10)
        try await save(outside, "forecast.tomorrow", .string("Partly Cloudy"), 10)
        try await save(outside, "forecast.tomorrow.high_f", .number(70), 10)
        try await save(mango, WorldFacts.characterRegion, .string("region:home"), 5)
        try await save(mango, WorldFacts.pronouns, .string("he/him"), 5)

        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        let page = try await knowledge.currentFacts(
            about: [mango, april, outside], mentionedIn: nil,
            limit: WorldKnowledgeLimits.maximumFacts)

        // The thirty are all things April taught them.
        let taught = page.filter { $0.predicate.hasPrefix("taught.") }
        #expect(taught.count == WorldKnowledgeLimits.maximumFacts)
        // The state is beside them, folded: one entry for the readings, one for the outlook.
        #expect(
            !page.contains {
                $0.predicate.hasPrefix("environment.") && $0.predicate != WorldFacts.environmentNow
            })
        #expect(page.filter { $0.predicate == WorldFacts.environmentNow }.count == 1)
        #expect(
            page.first { $0.predicate == WorldFacts.environmentNow }?.value
                .stringText?.contains("dimming") == true)
        #expect(
            page.first { $0.predicate == WorldFacts.forecastOutlook }?.value
                == .string("tonight: Mostly Clear; tomorrow: Partly Cloudy"))
        // The stage is beside them too: who is in the room, and how to name them.
        #expect(
            page.contains { $0.subjectID == mango && $0.predicate == WorldFacts.characterRegion })
        #expect(page.contains { $0.subjectID == mango && $0.predicate == WorldFacts.pronouns })
    }
}

extension WorldJSONValue {
    fileprivate var stringText: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}

/// #232: a fuller page - one memory once, one line per event.
@Suite("A fuller page")
struct FullerPageTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    private func fact(
        _ subject: String, _ predicate: String, _ value: WorldJSONValue,
        validTo: Date? = nil
    ) throws -> Fact {
        try Fact(
            subjectID: EntityID(validating: subject), predicate: predicate, value: value,
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
            validTo: validTo, derivedFrom: [],
            producer: FactProducer(kind: "presence", id: "given-facts", version: "1"))
    }

    @Test("A memory filed on three subjects is handed over once, the person's copy kept")
    func oneMemoryOnce() throws {
        let story: WorldJSONValue = .object([
            "day": .string("2026-10-15"), "salience": .number(0.85),
            "what": .string("April asked Kenny for a story."),
        ])
        let memories = [
            try fact("character:mango", "memory.episode.beaky.2026-10-15.6", story),
            try fact("person:april", "memory.episode.beaky.2026-10-15.6", story),
            try fact("character:beaky", "memory.episode.beaky.2026-10-15.6", story),
            // A belief slot on two subjects is two beliefs, never one.
            try fact(
                "person:april", "memory.belief.beaky.1", .object(["what": .string("one")])),
            try fact(
                "house:aprils-nest", "memory.belief.beaky.1", .object(["what": .string("two")])),
            try fact("place:front-door", "door.lock", .string("locked")),
        ]
        let once = PresentWorldKnowledge.oneOfEachMemory(memories)
        let episodes = once.filter { $0.predicate == "memory.episode.beaky.2026-10-15.6" }
        #expect(episodes.count == 1)
        #expect(episodes.first?.subjectID.rawValue == "person:april")
        #expect(once.filter { $0.predicate == "memory.belief.beaky.1" }.count == 2)
        #expect(once.contains { $0.predicate == "door.lock" })
        // And the episode budget counts it once: six distinct memories fit in six.
        let trimmed = PresentWorldKnowledge.withMemoriesTrimmed(
            memories, memory: MemoryConfiguration(), now: now)
        #expect(trimmed.filter { $0.predicate == "memory.episode.beaky.2026-10-15.6" }.count == 1)
    }

    @Test("An event is one line: title, when, where, with whom, which calendar")
    func eventFoldsIntoALine() throws {
        let ends = now.addingTimeInterval(86_400)
        let folded = PageFolding.foldCalendar([
            try fact("event:church-20261018", "calendar.title", .string("Church"), validTo: ends),
            try fact(
                "event:church-20261018", "calendar.when", .string("Sunday, October 18 at 9:30 AM"),
                validTo: ends),
            try fact(
                "event:church-20261018", "calendar.location",
                .string("Unitarian Universalist Congregation\nFreeland, WA"), validTo: ends),
            try fact(
                "event:church-20261018", "calendar.with", .string("person:jesse"), validTo: ends),
            try fact("event:church-20261018", "calendar.calendar", .string("Home"), validTo: ends),
            try fact(
                "reminder:office", "reminder.title", .string("chaise longue for office")),
            try fact("reminder:office", "reminder.due", .string("Friday, October 16")),
            try fact("reminder:office", "reminder.priority", .string("high")),
            try fact("reminder:office", "reminder.completed", .bool(false)),
            try fact("person:april", "presence.state", .string("home")),
        ])
        #expect(folded.count == 3)
        let event = try #require(folded.first { $0.predicate == WorldFacts.calendarEvent })
        #expect(
            event.value
                == .string(
                    "Church - Sunday, October 18 at 9:30 AM - at Unitarian Universalist Congregation, Freeland, WA - with Jesse - on the Home calendar"
                ))
        #expect(event.validTo == ends)
        #expect(event.derivedFrom.count == 5)
        let reminder = try #require(folded.first { $0.predicate == WorldFacts.reminderItem })
        #expect(
            reminder.value
                == .string("chaise longue for office - due Friday, October 16 - high priority"))
        #expect(folded.contains { $0.predicate == "presence.state" })
    }

    @Test("A forecast's period reads as words: next rain, not next_rain")
    func periodLabelsAreWords() throws {
        let outlook = PageFolding.outlook([
            try fact("place:outside", "forecast.next_rain", .string("not in the next two days"))
        ])
        #expect(outlook == "next rain: not in the next two days")
    }
}

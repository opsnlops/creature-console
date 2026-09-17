import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

@Suite("The world's side of memory")
struct MemoryConfigurationTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    @Test("The clock runs at 3:30 in the house's zone and names the day that ended")
    func nextRun() {
        let memory = MemoryConfiguration()
        // 2026-09-13 20:00 PDT → next run 2026-09-14 03:30 PDT, remembering the 13th.
        let evening = Date(timeIntervalSince1970: 1_789_354_800)
        let next = memory.nextRun(after: evening)
        #expect(next.day == "2026-09-13")
        #expect(next.dueAt == Date(timeIntervalSince1970: 1_789_381_800))
        // Just after a run, the next is a day later.
        let afterRun = next.dueAt.addingTimeInterval(60)
        #expect(memory.nextRun(after: afterRun).day == "2026-09-14")
        #expect(memory.nextRun(after: afterRun).dueAt == next.dueAt.addingTimeInterval(86_400))
        let bounds = MemoryConfiguration.bounds(ofDay: "2026-09-13", in: pacific)
        #expect(bounds?.from == Date(timeIntervalSince1970: 1_789_282_800))
        #expect(bounds?.to == Date(timeIntervalSince1970: 1_789_369_200))
        #expect(MemoryConfiguration.bounds(ofDay: "nonsense", in: pacific) == nil)
        let decoded = try? JSONDecoder().decode(
            MemoryConfiguration.self, from: Data("{\"hour\": 4, \"episodes_in_prompt\": 5}".utf8))
        #expect(decoded?.hour == 4)
        #expect(decoded?.minute == 30)
        #expect(decoded?.episodesInPrompt == 5)
    }

    @Test("Memories are kept for years but handed out sparingly: recent, salient, few")
    func memoriesAreTrimmed() throws {
        let jesse = try EntityID(validating: "person:jesse")
        let beaky = try EntityID(validating: "character:beaky")
        let now = Date(timeIntervalSince1970: 1_789_354_800)
        func episode(_ day: Int, salience: Double) throws -> Fact {
            try Fact(
                subjectID: jesse, predicate: "memory.episode.2026-09-\(day)",
                value: .object(["what": .string("day \(day)"), "salience": .number(salience)]),
                epistemic: EpistemicState(type: .remembered, confidence: 1),
                validFrom: now.addingTimeInterval(-TimeInterval(13 - day) * 86_400),
                derivedFrom: [], producer: FactProducer(kind: "test", id: "t", version: "1"))
        }
        let old = try Fact(
            subjectID: jesse, predicate: "memory.episode.2026-07-01",
            value: .object(["what": .string("long ago"), "salience": .number(1)]),
            epistemic: EpistemicState(type: .remembered, confidence: 1),
            validFrom: now.addingTimeInterval(-74 * 86_400), derivedFrom: [],
            producer: FactProducer(kind: "test", id: "t", version: "1"))
        let plain = try Fact(
            subjectID: jesse, predicate: WorldFacts.personDescription,
            value: .string("April's contractor"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
            derivedFrom: [], producer: FactProducer(kind: "test", id: "t", version: "1"))
        var reflections: [Fact] = []
        for day in 10...13 {
            reflections.append(
                try Fact(
                    subjectID: beaky, predicate: "memory.reflection.2026-09-\(day)",
                    value: .object(["text": .string("day \(day)")]),
                    epistemic: EpistemicState(type: .remembered, confidence: 1),
                    validFrom: now.addingTimeInterval(-TimeInterval(13 - day) * 86_400),
                    derivedFrom: [], producer: FactProducer(kind: "test", id: "t", version: "1")))
        }
        // Beliefs never age out: the oldest, most salient one is handed over before a fresh
        // trivial one, and the ancient one is still there.
        func belief(_ slot: Int, salience: Double, age: TimeInterval) throws -> Fact {
            try Fact(
                subjectID: jesse, predicate: "memory.belief.\(slot)",
                value: .object([
                    "kind": .string("relationship"), "what": .string("belief \(slot)"),
                    "salience": .number(salience),
                ]),
                epistemic: EpistemicState(type: .remembered, confidence: salience),
                validFrom: now.addingTimeInterval(-age), derivedFrom: [],
                producer: FactProducer(kind: "test", id: "t", version: "1"))
        }
        let beliefs = [
            try belief(1, salience: 0.9, age: 200 * 86_400), try belief(2, salience: 0.2, age: 0),
            try belief(3, salience: 0.6, age: 40 * 86_400),
        ]
        let facts =
            [plain, old] + (try (5...13).map { try episode($0, salience: $0 == 7 ? 0.9 : 0.3) })
            + reflections + beliefs
        let memory = MemoryConfiguration(
            episodeDays: 30, episodesInPrompt: 3, reflectionsInPrompt: 2, beliefsInPrompt: 2)

        let trimmed = PresentWorldKnowledge.withMemoriesTrimmed(facts, memory: memory, now: now)

        #expect(trimmed.contains { $0.predicate == WorldFacts.personDescription })
        #expect(!trimmed.contains { $0.predicate == "memory.episode.2026-07-01" })
        let episodes = trimmed.filter { $0.predicate.hasPrefix("memory.episode.") }
        // The salient one from the 7th, then the two newest.
        #expect(
            episodes.map(\.predicate).sorted()
                == [
                    "memory.episode.2026-09-12", "memory.episode.2026-09-13",
                    "memory.episode.2026-09-7",
                ])
        let kept = trimmed.filter { $0.predicate.hasPrefix("memory.reflection.") }
        #expect(
            kept.map(\.predicate).sorted() == [
                "memory.reflection.2026-09-12", "memory.reflection.2026-09-13",
            ])
        #expect(
            trimmed.filter { $0.predicate.hasPrefix("memory.belief.") }.map(\.predicate)
                == ["memory.belief.1", "memory.belief.3"])
        #expect(WorldFacts.memoryFamily(of: "memory.belief.1") == WorldFacts.memoryBelief)
        #expect(
            WorldFacts.memoryFamily(of: "memory.episode.2026-09-13") == WorldFacts.memoryEpisode)
        #expect(WorldFacts.memoryFamily(of: "door.lock") == nil)
    }
}

@Suite(
    "Memories beside the day's facts",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct MemoriesBesideFactsTests {
    @Test("A night of episodes does not push what April taught the birds off the page")
    func memoriesDoNotCrowdOutFacts() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "memory-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start.addingTimeInterval(7_200))
        func fact(_ predicate: String, _ value: WorldJSONValue, at offset: TimeInterval) throws
            -> Fact
        {
            try Fact(
                subjectID: april, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: start.addingTimeInterval(offset), derivedFrom: [],
                producer: FactProducer(kind: "test", id: "memory", version: "1"))
        }
        // What April taught them in the evening, then a night's memory of it - more episodes
        // than the page holds, every one newer than the car.
        try await persistence.facts.save(
            try fact("vehicle.model", .string("Volkswagen ID.4"), at: 0))
        for slot in 1...(WorldKnowledgeLimits.maximumFacts + 5) {
            try await persistence.facts.save(
                try fact(
                    "memory.episode.2026-09-13.\(slot)",
                    .object(["what": .string("episode \(slot)"), "salience": .number(0.5)]),
                    at: 3_600 + Double(slot)))
        }
        var memory = MemoryConfiguration()
        memory.episodesInPrompt = 3
        var knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        knowledge.memory = memory

        let handed = try await knowledge.currentFacts(
            about: [april], mentionedIn: nil, limit: WorldKnowledgeLimits.maximumFacts)
        #expect(handed.contains { $0.predicate == "vehicle.model" })
        #expect(handed.filter { $0.predicate.hasPrefix("memory.episode.") }.count == 3)
    }
}

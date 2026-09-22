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
                subjectID: jesse, predicate: "memory.episode.beaky.2026-09-\(day)",
                value: .object(["what": .string("day \(day)"), "salience": .number(salience)]),
                epistemic: EpistemicState(type: .remembered, confidence: 1),
                validFrom: now.addingTimeInterval(-TimeInterval(13 - day) * 86_400),
                derivedFrom: [], producer: FactProducer(kind: "test", id: "t", version: "1"))
        }
        let old = try Fact(
            subjectID: jesse, predicate: "memory.episode.beaky.2026-07-01",
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
                    subjectID: beaky, predicate: "memory.reflection.beaky.2026-09-\(day)",
                    value: .object(["text": .string("day \(day)")]),
                    epistemic: EpistemicState(type: .remembered, confidence: 1),
                    validFrom: now.addingTimeInterval(-TimeInterval(13 - day) * 86_400),
                    derivedFrom: [], producer: FactProducer(kind: "test", id: "t", version: "1")))
        }
        // Beliefs never age out: the oldest, most salient one is handed over before a fresh
        // trivial one, and the ancient one is still there.
        func belief(_ slot: Int, salience: Double, age: TimeInterval) throws -> Fact {
            try Fact(
                subjectID: jesse, predicate: "memory.belief.beaky.\(slot)",
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
        #expect(!trimmed.contains { $0.predicate == "memory.episode.beaky.2026-07-01" })
        let episodes = trimmed.filter { $0.predicate.hasPrefix("memory.episode.beaky.") }
        // The salient one from the 7th, then the two newest.
        #expect(
            episodes.map(\.predicate).sorted()
                == [
                    "memory.episode.beaky.2026-09-12", "memory.episode.beaky.2026-09-13",
                    "memory.episode.beaky.2026-09-7",
                ])
        let kept = trimmed.filter { $0.predicate.hasPrefix("memory.reflection.beaky.") }
        #expect(
            kept.map(\.predicate).sorted() == [
                "memory.reflection.beaky.2026-09-12", "memory.reflection.beaky.2026-09-13",
            ])
        #expect(
            trimmed.filter { $0.predicate.hasPrefix("memory.belief.beaky.") }.map(\.predicate)
                == ["memory.belief.beaky.1", "memory.belief.beaky.3"])
        #expect(WorldFacts.memoryFamily(of: "memory.belief.beaky.1") == WorldFacts.memoryBelief)
        #expect(
            WorldFacts.memoryFamily(of: "memory.episode.beaky.2026-09-13")
                == WorldFacts.memoryEpisode)
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
                    "memory.episode.beaky.2026-09-13.\(slot)",
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

        let beaky = try EntityID(validating: "character:beaky")
        let handed = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: nil, limit: WorldKnowledgeLimits.maximumFacts)
        #expect(handed.contains { $0.predicate == "vehicle.model" })
        #expect(handed.filter { $0.predicate.hasPrefix("memory.episode.beaky.") }.count == 3)
    }

    @Test("A mind is handed its own memories, never another bird's; nobody's without a mind")
    func memoriesAreTheMindsOwn() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "memory-owner-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let beaky = try EntityID(validating: "character:beaky")
        let kenny = try EntityID(validating: "character:kenny")
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start.addingTimeInterval(7_200))
        func fact(_ predicate: String, by bird: String) throws -> Fact {
            try Fact(
                subjectID: april, predicate: predicate,
                value: .object(["what": .string("by \(bird)"), "salience": .number(0.5)]),
                epistemic: EpistemicState(type: .remembered, confidence: 1),
                validFrom: start.addingTimeInterval(3_600), derivedFrom: [],
                producer: FactProducer(kind: "mind", id: bird, version: "1"))
        }
        try await persistence.facts.save(try fact("memory.episode.beaky.2026-09-13.1", by: "beaky"))
        try await persistence.facts.save(try fact("memory.belief.beaky.1", by: "beaky"))
        try await persistence.facts.save(try fact("memory.episode.kenny.2026-09-13.1", by: "kenny"))
        try await persistence.facts.save(try fact("memory.belief.kenny.1", by: "kenny"))
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        let kennys = try await knowledge.currentFacts(
            about: [kenny, april], mentionedIn: nil, limit: WorldKnowledgeLimits.maximumFacts)
        #expect(
            Set(kennys.filter { $0.subjectID == april }.map(\.predicate)) == [
                "memory.episode.kenny.2026-09-13.1", "memory.belief.kenny.1",
            ])
        let beakys = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: nil, limit: WorldKnowledgeLimits.maximumFacts)
        #expect(
            Set(beakys.filter { $0.subjectID == april }.map(\.predicate)) == [
                "memory.episode.beaky.2026-09-13.1", "memory.belief.beaky.1",
            ])
        // No mind among the subjects: no memories at all.
        let nobodys = try await knowledge.currentFacts(
            about: [april], mentionedIn: nil, limit: WorldKnowledgeLimits.maximumFacts)
        #expect(!nobodys.contains { WorldFacts.memoryFamily(of: $0.predicate) != nil })
        // What Kenny remembers, on any subject: the memories resource.
        let remembered = try await persistence.facts.currentFacts(
            rememberedBy: kenny, limit: 50, at: await clock.now)
        #expect(remembered.contains { $0.predicate == "memory.belief.kenny.1" })
        #expect(!remembered.contains { $0.predicate.contains(".beaky.") })
    }

    @Test("Memories from before they were owned are renamed to their bird's, once")
    func migrationOwnsMemories() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "memory-migration-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        // As the world really stores them: the producer is the given-facts reducer, whoever
        // told it (the mind is on the event, not the fact).
        func fact(_ predicate: String) throws -> Fact {
            try Fact(
                subjectID: april, predicate: predicate, value: .string("old"),
                epistemic: EpistemicState(type: .remembered, confidence: 1),
                validFrom: start, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        }
        let episode = try fact("memory.episode.2026-09-13.2")
        let reflection = try fact("memory.reflection.2026-09-13")
        let belief = try fact("memory.belief.4")
        let owned = try fact("memory.belief.kenny.1")
        // And one the first cut of the migration misnamed after the reducer.
        let misowned = try fact("memory.episode.given-facts.2026-09-12.1")
        for f in [episode, reflection, belief, owned, misowned] {
            try await persistence.facts.save(f)
        }
        let migrator = MongoWorldMigrator(
            database: persistence.database, logger: .init(label: "memory-migration-tests"))
        try await migrator.ownMemories()
        try await migrator.ownMemories()  // idempotent
        let after = try await persistence.facts.currentFacts(subjectID: april, at: start + 60)
        #expect(
            Set(after.map(\.predicate)) == [
                "memory.episode.beaky.2026-09-13.2", "memory.reflection.beaky.2026-09-13",
                "memory.belief.beaky.4", "memory.belief.kenny.1",
                "memory.episode.beaky.2026-09-12.1",
            ])
        #expect(
            after.first { $0.factID == episode.factID }?.predicate
                == "memory.episode.beaky.2026-09-13.2")
    }
}

@Suite("Whose memory a predicate is")
struct MemoryOwnerTests {
    @Test("The owner is the segment after the family; the old form has none")
    func owner() throws {
        #expect(WorldFacts.memoryOwner(of: "memory.episode.kenny.2026-09-13.2") == "kenny")
        #expect(WorldFacts.memoryOwner(of: "memory.reflection.beaky.2026-09-13") == "beaky")
        #expect(WorldFacts.memoryOwner(of: "memory.belief.mango.1") == "mango")
        #expect(WorldFacts.memoryOwner(of: "memory.episode.2026-09-13.2") == nil)
        #expect(WorldFacts.memoryOwner(of: "memory.belief.1") == nil)
        #expect(WorldFacts.memoryOwner(of: "door.lock") == nil)
        let kenny = try EntityID(validating: "character:kenny")
        #expect(
            WorldFacts.memoryPrefix(WorldFacts.memoryEpisode, of: kenny) == "memory.episode.kenny.")
        #expect(WorldFacts.memoryFamily(of: "memory.belief.kenny.1") == WorldFacts.memoryBelief)
        #expect(FactRepository.ownMemoriesPattern(of: kenny) == "^memory\\.[a-z]+\\.kenny\\.")
    }
}

@Suite(
    "Phase 9's last slice: retrieval, and what a bird said lately",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct RetrievalTests {
    @Test("The words of the moment call up an old memory of the mind's own; not another bird's")
    func retrievesByWords() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "retrieval-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let beaky = try EntityID(validating: "character:beaky")
        let kenny = try EntityID(validating: "character:kenny")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: now)
        // A word nobody else's facts carry, so the text index finds only these.
        let word = "zebrawood\(suffix.prefix(6))"
        func memory(_ predicate: String, what: String, daysAgo: Int, by bird: String) throws
            -> Fact
        {
            try Fact(
                subjectID: april, predicate: predicate,
                value: .object(["what": .string(what), "salience": .number(0.3)]),
                epistemic: EpistemicState(type: .remembered, confidence: 1),
                validFrom: now.addingTimeInterval(-Double(daysAgo) * 86_400), derivedFrom: [],
                producer: FactProducer(kind: "mind", id: bird, version: "1"))
        }
        // Beaky's, sixty days old - far past episode_days; Kenny's, the same words.
        try await persistence.facts.save(
            try memory(
                "memory.episode.beaky.2026-07-15.1", what: "April finished the \(word) shelf",
                daysAgo: 60, by: "beaky"))
        try await persistence.facts.save(
            try memory(
                "memory.episode.kenny.2026-07-15.1", what: "Kenny watched the \(word) shelf",
                daysAgo: 60, by: "kenny"))
        var memory = MemoryConfiguration()
        memory.retrievedInPrompt = 4
        var knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        knowledge.memory = memory
        let asked = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: "how did the \(word) shelf turn out?",
            limit: WorldKnowledgeLimits.maximumFacts)
        #expect(asked.contains { $0.predicate == "memory.episode.beaky.2026-07-15.1" })
        #expect(!asked.contains { $0.predicate == "memory.episode.kenny.2026-07-15.1" })
        // Without the words, the old episode is past its days and stays on the shelf.
        let unasked = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: "what time is it?",
            limit: WorldKnowledgeLimits.maximumFacts)
        #expect(!unasked.contains { $0.predicate == "memory.episode.beaky.2026-07-15.1" })
        // Turned off, nothing is called up.
        knowledge.memory.retrievedInPrompt = 0
        let off = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: "how did the \(word) shelf turn out?",
            limit: WorldKnowledgeLimits.maximumFacts)
        #expect(!off.contains { $0.predicate == "memory.episode.beaky.2026-07-15.1" })
    }

    @Test("What a bird said lately comes from its own turns, across scenes, oldest first")
    func recentLinesAreTheBirdsOwn() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "recent-lines-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let kenny = try EntityID(validating: "character:kenny-\(suffix)")
        let mango = try EntityID(validating: "character:mango-\(suffix)")
        let region = try EntityID(validating: "region:home-\(suffix)")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        func turn(_ speaker: EntityID, _ text: String?, at: Date) throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: SceneService.turnEventType, occurredAt: at,
                source: EventSource(
                    id: try SourceID(validating: "world:scenes"), kind: "world",
                    sourceEventID: UUID().uuidString),
                subjectIDs: [speaker, kenny, mango], placeID: region,
                epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: [
                    "character_id": .string(speaker.rawValue),
                    "text": text.map { .string($0) } ?? .null,
                    "pass": .bool(text == nil),
                ])
        }
        for event in [
            try turn(kenny, "Kenny likes shiny.", at: now - 300),
            try turn(mango, "Debian would have finished by now.", at: now - 240),
            try turn(kenny, nil, at: now - 180),  // a pass says nothing
            try turn(kenny, "Maybe it is a robot feather.", at: now - 120),
        ] {
            _ = try await persistence.events.append(event, receivedAt: event.occurredAt)
        }
        let lines = try await persistence.events.spokenLines(of: kenny, limit: 8)
        #expect(lines.map(\.text) == ["Maybe it is a robot feather.", "Kenny likes shiny."])
        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        // Oldest first for the prompt; only one at a time when asked for one.
        #expect(
            try await knowledge.recentLines(of: kenny, limit: 8).map(\.text) == [
                "Kenny likes shiny.", "Maybe it is a robot feather.",
            ])
        #expect(
            try await knowledge.recentLines(of: kenny, limit: 1).map(\.text) == [
                "Maybe it is a robot feather."
            ])
        #expect(try await knowledge.recentLines(of: mango, limit: 8).count == 1)
    }
}

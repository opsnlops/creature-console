import Foundation
import Testing
import WorldCore

@testable import creature_world

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
        let facts =
            [plain, old] + (try (5...13).map { try episode($0, salience: $0 == 7 ? 0.9 : 0.3) })
            + reflections
        let memory = MemoryConfiguration(
            episodeDays: 30, episodesInPrompt: 3, reflectionsInPrompt: 2)

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
            WorldFacts.memoryFamily(of: "memory.episode.2026-09-13") == WorldFacts.memoryEpisode)
        #expect(WorldFacts.memoryFamily(of: "door.lock") == nil)
    }
}

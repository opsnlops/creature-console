import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

@Suite(
    "Search over the facts",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct WorldSearchTests {
    @Test("A word finds entities by any string in their current facts, best first, stemmed")
    func searchesEveryString() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "search-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        // A run-unique word, so other runs' facts in the shared database never answer.
        let word = "zq\(UUID().uuidString.prefix(8).lowercased().filter(\.isLetter))"
        let tamara = try EntityID(validating: "person:tamara-\(word)")
        let order = try EntityID(validating: "order:amazon-\(word)")
        func fact(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue) throws
            -> Fact
        {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: now.addingTimeInterval(-60), derivedFrom: [],
                producer: FactProducer(kind: "test", id: "search", version: "1"))
        }
        try await persistence.facts.save(
            try fact(tamara, "person.relationship", .string("the cleaners \(word)")))
        try await persistence.facts.save(try fact(tamara, "contact.name", .string("Tamara")))
        try await persistence.facts.save(
            try fact(
                order, "order.items",
                .array([.string("Crest toothpaste \(word)"), .string("floss")])))
        // A superseded fact never answers.
        let gone = try fact(order, "order.status", .string("placed \(word)"))
        try await persistence.facts.save(gone)
        try await persistence.facts.supersede(
            by: try fact(order, "order.status", .string("shipped")))

        // The word finds both, grouped by entity, with the facts that matched.
        let both = try await persistence.facts.search(word, limit: 20, at: now)
        #expect(Set(both.map(\.0.subjectID)) == [tamara, order])
        #expect(!both.contains { $0.0.factID == gone.factID })
        #expect(both.allSatisfy { $0.1 > 0 })

        // Stemming: "cleaner" finds "the cleaners", and outranks the order that only
        // matched the run's word; the order's item by its word.
        let cleaner = try await persistence.facts.search("cleaner \(word)", limit: 20, at: now)
        #expect(cleaner.first?.0.subjectID == tamara)
        #expect(cleaner.first?.0.predicate == "person.relationship")
        let paste = try await persistence.facts.search("toothpaste \(word)", limit: 20, at: now)
        #expect(paste.first?.0.subjectID == order)
        #expect(paste.first?.0.predicate == "order.items")
    }
}

@Suite(
    "A recurring event answers once, with its next instance",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct SearchRankingTests {
    @Test("A real search over a year of instances returns the next one, not yesterday's (#206)")
    func collapsesRecurringInstances() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "search-ranking-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let now = Date(timeIntervalSince1970: 1_790_103_600)  // 2026-09-22 12:00 PDT
        // A run-unique trainer, so other runs' facts never answer.
        let trainer = "Adlai \(UUID().uuidString.prefix(8).lowercased().filter(\.isLetter))q"
        let title = "Personal Training - 60 Minutes(\(trainer) - Accepted)"
        let series = "series\(UUID().uuidString.prefix(8).lowercased())"
        // As the Bridge casts them: title and start on each instance, the start world-only.
        func instance(daysFromNow days: Int) async throws -> EntityID {
            let event = try EntityID(validating: "event:\(series)-\(days + 1000)")
            for (predicate, value) in [
                (WorldFacts.calendarTitle, WorldJSONValue.string(title)),
                (
                    WorldFacts.calendarStartsAt,
                    .string(WorldJSON.timestamp(now.addingTimeInterval(Double(days) * 86_400)))
                ),
            ] {
                try await persistence.facts.save(
                    try Fact(
                        subjectID: event, predicate: predicate, value: value,
                        epistemic: EpistemicState(type: .reported, confidence: 1),
                        validFrom: now.addingTimeInterval(-86_400), derivedFrom: [],
                        producer: FactProducer(kind: "reducer", id: "given-facts", version: "1")))
            }
            return event
        }
        // Twice a week for a year, as the Bridge casts it: more instances than a text search
        // returns, all scoring the same - so the nearest is usually not among the ones the
        // words found. Thursday's must answer anyway.
        var others: [EntityID] = []
        for days in stride(from: -91, through: 365, by: 3) where days != 2 {
            others.append(try await instance(daysFromNow: days))
        }
        // Yesterday's session (-1) is closer in time; Thursday's is the next one.
        let thursday = try await instance(daysFromNow: 2)
        let page = try await PresentWorldKnowledge.search(
            trainer, limit: 10, facts: persistence.facts, now: now)
        let mine = page.hits.filter { $0.entityID.rawValue.hasPrefix("event:\(series)") }
        // One training, Thursday's - not a past one or one next year.
        #expect(mine.map(\.entityID) == [thursday])
        #expect(!others.contains { id in page.hits.contains { $0.entityID == id } })
        #expect(mine.first?.facts.first?.value == .string(title))
        // A year of instances left behind would crowd other tests' calendars (the departure
        // rule reads the next 500 starts): every fact this test made is ended.
        for event in others + [thursday] {
            for predicate in [WorldFacts.calendarTitle, WorldFacts.calendarStartsAt] {
                try await persistence.facts.supersede(
                    by: try Fact(
                        subjectID: event, predicate: predicate, value: .null,
                        epistemic: EpistemicState(type: .reported, confidence: 1),
                        validFrom: now.addingTimeInterval(-86_400 - 2),
                        validTo: now.addingTimeInterval(-86_400 - 1), derivedFrom: [],
                        producer: FactProducer(kind: "test", id: "cleanup", version: "1")))
            }
        }
        // The start was used to rank, never added to what a mind is handed.
        #expect(!mine[0].facts.contains { $0.predicate == WorldFacts.calendarStartsAt })
    }
}

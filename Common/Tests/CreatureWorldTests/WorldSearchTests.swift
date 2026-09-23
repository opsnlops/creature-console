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

@Suite("A recurring event answers once, with the instance nearest now")
struct SearchRankingTests {
    private let now = Date(timeIntervalSince1970: 1_790_103_600)  // 2026-09-22 12:00 PDT

    private func hit(_ id: String, title: String?, startsAt: Date?, score: Double)
        throws -> WorldSearchHit
    {
        let entity = try EntityID(validating: id)
        func fact(_ predicate: String, _ value: WorldJSONValue) throws -> Fact {
            try Fact(
                subjectID: entity, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
                derivedFrom: [],
                producer: FactProducer(kind: "test", id: "search", version: "1"))
        }
        var facts: [Fact] = []
        if let title { facts.append(try fact(WorldFacts.calendarTitle, .string(title))) }
        if let startsAt {
            facts.append(
                try fact(WorldFacts.calendarStartsAt, .string(WorldJSON.timestamp(startsAt))))
        }
        if facts.isEmpty { facts = [try fact("person.relationship", .string("the trainer"))] }
        return WorldSearchHit(entityID: entity, score: score, facts: facts)
    }

    @Test("Instances of one series collapse to the nearest; ties break by proximity")
    func collapsesRecurringInstances() throws {
        let title = "Personal Training - 60 Minutes(Adlai Erickson - Accepted)"
        // As the world really holds them: a year of identical instances, all scored the same.
        let hits = [
            try hit(
                "event:training-20270309", title: title, startsAt: now + 168 * 86_400, score: 1.14),
            try hit(
                "event:training-20260721", title: title, startsAt: now - 63 * 86_400, score: 1.14),
            try hit(
                "event:training-20260924", title: title, startsAt: now + 2 * 86_400, score: 1.14),
            try hit("person:adlai", title: nil, startsAt: nil, score: 1.14),
            try hit("event:therapy-20260923", title: "Therapy", startsAt: now + 86_400, score: 0.9),
        ]
        let ranked = PresentWorldKnowledge.oneInstancePerSeries(hits, now: now)
        // One training, the one two days out - not July's and not next March's.
        let training = ranked.filter { $0.entityID.rawValue.hasPrefix("event:training-") }
        #expect(training.map { $0.entityID.rawValue } == ["event:training-20260924"])
        // Everything else is untouched: the trainer himself, and a different series.
        #expect(ranked.count == 3)
        #expect(ranked.contains { $0.entityID.rawValue == "person:adlai" })
        #expect(ranked.contains { $0.entityID.rawValue == "event:therapy-20260923" })
        // Proximity, for the tie-break: two days beats a hundred and sixty-eight.
        #expect(
            PresentWorldKnowledge.distance(of: training[0], from: now)
                < PresentWorldKnowledge.distance(of: hits[0], from: now))
    }
}

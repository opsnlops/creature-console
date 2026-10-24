import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

/// #229: a fact says who kept it, and what the minds kept is found again when it matters.
@Suite("Learning that lasts: origin and retrieval")
struct LearningThatLastsTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    private func given(
        subject: String, predicate: String, value: WorldJSONValue, by source: String,
        at date: Date? = nil
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType,
            occurredAt: date ?? now,
            source: EventSource(
                id: SourceID(validating: source), kind: source.components(separatedBy: ":")[0],
                sourceEventID: UUID().uuidString),
            subjectIDs: [try EntityID(validating: subject)],
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: [
                "subject_id": .string(subject), "predicate": .string(predicate), "value": value,
            ])
    }

    @Test("A given fact keeps who said it; the ending of a visit says who ended it")
    func reducerKeepsTheOrigin() throws {
        let kept = try given(
            subject: "person:april", predicate: "flight.hardest_part", value: .string("landings"),
            by: "mind:beaky")
        let fact = try #require(try GivenFactReducer().reduce(kept).changedFacts.first)
        #expect(fact.origin == (try SourceID(validating: "mind:beaky")))
        // The producer is still the reducer: the origin is who said it, not who cast it.
        #expect(fact.producer.id == "given-facts")

        let old = try Fact(
            subjectID: EntityID(validating: "thing:propane-supplier"),
            predicate: "visitor.purpose", value: .string("refilling the big tank"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
            derivedFrom: [], producer: FactProducer(kind: "presence", id: "x", version: "1"))
        let ended = try given(
            subject: "thing:propane-supplier", predicate: "visitor.expected", value: .null,
            by: "mind:mango")
        let retraction = try #require(try GivenFactReducer().reduce(ended).retractions.first)
        #expect(try retraction.ending(old, by: ended).origin == SourceID(validating: "mind:mango"))
    }

    @Test("A fact from before origins decodes with none; one with an origin round-trips")
    func originIsOptionalOnTheWire() throws {
        let fact = try Fact(
            subjectID: EntityID(validating: "person:april"), predicate: "flight.hope",
            value: .string("hopes to own a plane someday"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
            derivedFrom: [],
            producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
            origin: SourceID(validating: "mind:beaky"))
        let encoded = try WorldJSON.makeEncoder().encode(fact)
        #expect(try WorldJSON.makeDecoder().decode(Fact.self, from: encoded) == fact)
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["origin"] as? String == "mind:beaky")
        object.removeValue(forKey: "origin")
        let older = try WorldJSON.makeDecoder().decode(
            Fact.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.origin == nil)
    }

    @Test("Six learned facts are called up by the words of the moment unless told otherwise")
    func retrievalIsConfigured() throws {
        #expect(MemoryConfiguration().factsRetrievedInPrompt == 6)
        let decoded = try JSONDecoder().decode(
            MemoryConfiguration.self, from: Data(#"{"facts_retrieved_in_prompt": 0}"#.utf8))
        #expect(decoded.factsRetrievedInPrompt == 0)
    }
}

@Suite(
    "Learning that lasts, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct LearningThatLastsMongoTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)

    private func fact(
        _ subject: EntityID, _ predicate: String, _ value: WorldJSONValue, daysAgo: Double = 0,
        origin: String?
    ) throws -> Fact {
        try Fact(
            subjectID: subject, predicate: predicate, value: value,
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: now.addingTimeInterval(-daysAgo * 86_400), derivedFrom: [],
            producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
            origin: try origin.map { try SourceID(validating: $0) })
    }

    private func connect() async throws -> MongoWorldPersistence {
        let uri = try #require(mongoTestURI)
        return try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "learning-tests"))
    }

    @Test(
        "A month-old learned fact is on the page when the words call it up, past the newest thirty"
    )
    func oldLearnedFactsAreCalledUp() async throws {
        let persistence = try await connect()
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let beaky = try EntityID(validating: "character:beaky")
        // A word nobody else's facts carry, so the text index finds only these.
        let word = "cherokee\(suffix.prefix(6))"
        try await persistence.facts.save(
            try fact(
                april, "flight.aircraft", .string("flies a 1968 Piper \(word)"), daysAgo: 30,
                origin: "mind:beaky"))
        // Forty newer facts crowd it off the newest thirty.
        for index in 0..<40 {
            try await persistence.facts.save(
                try fact(
                    april, "misc.note_\(index)", .string("note \(index)"), daysAgo: 0,
                    origin: "mind:kenny"))
        }
        let clock = ManualWorldClock(now: now)
        var knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        let asked = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: "how is the \(word) doing?",
            limit: WorldKnowledgeLimits.maximumFacts)
        try await expectPageCovers(
            knowledge, about: [beaky, april], words: "how is the \(word) doing?",
            checking: [beaky, april])
        #expect(asked.contains { $0.predicate == "flight.aircraft" && $0.subjectID == april })
        let unasked = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: "what time is it?",
            limit: WorldKnowledgeLimits.maximumFacts)
        #expect(!unasked.contains { $0.predicate == "flight.aircraft" && $0.subjectID == april })
        knowledge.memory.factsRetrievedInPrompt = 0
        let off = try await knowledge.currentFacts(
            about: [beaky, april], mentionedIn: "how is the \(word) doing?",
            limit: WorldKnowledgeLimits.maximumFacts)
        #expect(!off.contains { $0.predicate == "flight.aircraft" && $0.subjectID == april })
    }

    @Test("What the minds kept, by origin: never the Bridge's, never a memory, never history")
    func learnedByOrigin() async throws {
        let persistence = try await connect()
        defer { Task { await persistence.cluster.disconnect() } }
        let subject = try EntityID(validating: "person:origin-\(UUID().uuidString.lowercased())")
        let kept = try fact(subject, "flight.hope", .string("own a plane"), origin: "mind:beaky")
        try await persistence.facts.save(kept)
        try await persistence.facts.save(
            try fact(subject, "contact.name", .string("April"), origin: "bridge:contacts"))
        try await persistence.facts.save(
            try fact(
                subject, "memory.episode.beaky.2026-10-14.1", .object(["what": .string("x")]),
                origin: "mind:beaky"))
        let replaced = try fact(
            subject, "flight.school_gap", .string("a month"), daysAgo: 1, origin: "mind:mango")
        try await persistence.facts.save(replaced)
        let replacement = try fact(
            subject, "flight.school_gap", .string("flying again"), origin: "mind:kenny")
        try await persistence.facts.supersede(by: replacement)
        try await persistence.facts.save(replacement)

        var learned: [Fact] = []
        var after: FactID?
        repeat {
            let page = try await persistence.facts.currentFacts(
                originPrefix: "mind:", after: after, limit: 500, at: now)
            learned += page
            after = page.count == 500 ? page.last?.factID : nil
        } while after != nil
        let mine = learned.filter { $0.subjectID == subject }
        #expect(Set(mine.map(\.predicate)) == ["flight.hope", "flight.school_gap"])
        #expect(
            mine.first { $0.predicate == "flight.school_gap" }?.value == .string("flying again"))

        // What a later keeping replaced, with what replaced it.
        let overwritten = try await persistence.facts.overwrittenFacts(
            originPrefix: "mind:", since: now.addingTimeInterval(-3_600), limit: 500
        ).filter { $0.replaced.subjectID == subject }
        #expect(overwritten.count == 1)
        #expect(overwritten.first?.replaced.value == .string("a month"))
        #expect(overwritten.first?.by.factID == replacement.factID)
    }

    @Test("An ending is not a writing-over: a visit ended with none is not folded back")
    func endingsAreNotOverwrites() async throws {
        let persistence = try await connect()
        defer { Task { await persistence.cluster.disconnect() } }
        let subject = try EntityID(validating: "person:ending-\(UUID().uuidString.lowercased())")
        try await persistence.facts.save(
            try fact(
                subject, "visitor.expected", .string("today"), daysAgo: 0.01, origin: "mind:beaky"))
        let ended = try fact(subject, "visitor.expected", .null, origin: "mind:beaky")
        try await persistence.facts.supersede(by: ended)
        try await persistence.facts.save(ended)
        let overwritten = try await persistence.facts.overwrittenFacts(
            originPrefix: "mind:", since: now.addingTimeInterval(-3_600), limit: 500
        ).filter { $0.replaced.subjectID == subject }
        #expect(overwritten.isEmpty)
    }

    @Test("A fact from before origins is given its event's source; a lost event is noted once")
    func backfillsTheOrigin() async throws {
        let persistence = try await connect()
        defer { Task { await persistence.cluster.disconnect() } }
        let subject = try EntityID(validating: "person:backfill-\(UUID().uuidString.lowercased())")
        let event = try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType, occurredAt: now,
            source: EventSource(
                id: SourceID(validating: "mind:caroll"), kind: "mind",
                sourceEventID: UUID().uuidString),
            subjectIDs: [subject], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: [
                "subject_id": .string(subject.rawValue), "predicate": .string("flight.rules"),
                "value": .string("VFR"),
            ])
        _ = try await persistence.events.append(event, receivedAt: now)
        let old = try Fact(
            subjectID: subject, predicate: "flight.rules", value: .string("VFR"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
            derivedFrom: [.event(event.eventID)],
            producer: FactProducer(kind: "presence", id: "given-facts", version: "1"))
        try await persistence.facts.save(old)
        let orphan = try Fact(
            subjectID: subject, predicate: "flight.hope", value: .string("a plane"),
            epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
            derivedFrom: [.event(.generated())],
            producer: FactProducer(kind: "presence", id: "given-facts", version: "1"))
        try await persistence.facts.save(orphan)

        _ = try await persistence.facts.backfillOrigin(
            events: persistence.database[MongoWorldCollection.events])
        let after = try await persistence.facts.currentFacts(subjectID: subject, at: now)
        #expect(
            after.first { $0.predicate == "flight.rules" }?.origin
                == (try SourceID(validating: "mind:caroll")))
        #expect(after.first { $0.predicate == "flight.hope" }?.origin == nil)
        // Looked for once: a second run finds nothing more to do for these.
        _ = try await persistence.facts.backfillOrigin(
            events: persistence.database[MongoWorldCollection.events])
        #expect(
            try await persistence.facts.currentFacts(subjectID: subject, at: now)
                .first { $0.predicate == "flight.hope" }?.origin == nil)
    }
}

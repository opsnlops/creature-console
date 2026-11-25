import Foundation
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

/// News told late says nothing about what was learned since (#300). Twice on a Sunday morning the
/// house restarted while April was out and said again, as of when it happened, that she had left.
/// That ended where she had since told Beaky she was, before it began; the fact could not be read
/// back, and the night's filing was lost with the page it was on.
@Suite(
    "News told late, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct LateNewsMongoTests {
    // Now, in whole seconds: events expire by kind, and an old one can be swept mid-test.
    private let left = Date(
        timeIntervalSince1970: (Date().timeIntervalSince1970 - 7_200).rounded(.down))

    private func withWorld(
        _ body: (World, MongoWorldPersistence, EntityID) async throws -> Void
    ) async throws {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "late-news-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let april = try EntityID(validating: "person:april-\(UUID().uuidString.lowercased())")
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [HouseReducer(), GivenFactReducer()],
            clock: ManualWorldClock(now: left.addingTimeInterval(7_200)))
        try await body(world, persistence, april)
    }

    private func house(
        _ type: WorldEventType, _ person: EntityID, at date: Date, key: String
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: type, occurredAt: date,
            source: EventSource(
                id: SourceID(validating: "home-assistant:\(person.rawValue.dropFirst(7))"),
                kind: HouseEvents.sourceKind, sourceEventID: key),
            subjectIDs: [person], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:])
    }

    private func told(_ value: WorldJSONValue, _ person: EntityID, at date: Date) throws
        -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: GivenFactAnnouncement.eventType, occurredAt: date,
            source: EventSource(
                id: SourceID(validating: "mind:beaky"), kind: "mind",
                sourceEventID: UUID().uuidString),
            subjectIDs: [person], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: [
                "subject_id": .string(person.rawValue), "predicate": .string("presence.place"),
                "value": value, "valid_for_seconds": .number(7_200),
            ])
    }

    private func place(_ persistence: MongoWorldPersistence, _ person: EntityID, at date: Date)
        async throws -> WorldJSONValue?
    {
        try await persistence.facts.currentFacts(subjectID: person, at: date)
            .first { $0.predicate == "presence.place" }?.value
    }

    @Test("A restart's old leaving does not end where she has said she is since")
    func lateLeavingKeepsTheNewerPlace() async throws {
        try await withWorld { world, persistence, april in
            _ = try await world.accept(
                try house(HouseEvents.personLeft, april, at: left, key: "context:1"))
            _ = try await world.accept(
                try told(.string("at the library"), april, at: left.addingTimeInterval(900)))
            // The house starts again and says what it sees, as of when it changed.
            let again = try await world.accept(
                try house(HouseEvents.personLeft, april, at: left, key: "snapshot:1"))
            #expect(again.disposition == .accepted)

            #expect(
                try await place(persistence, april, at: left.addingTimeInterval(1_800))
                    == .string("at the library"))
        }
    }

    @Test("Coming home still ends where she had said she was")
    func arrivalEndsTheToldPlace() async throws {
        try await withWorld { world, persistence, april in
            _ = try await world.accept(
                try told(.string("at the library"), april, at: left.addingTimeInterval(900)))
            let home = left.addingTimeInterval(1_800)
            _ = try await world.accept(
                try house(HouseEvents.personArrived, april, at: home, key: "context:2"))
            #expect(try await place(persistence, april, at: home.addingTimeInterval(5)) == nil)
        }
    }

    @Test("A fact is never ended before it began, whatever supersedes it, and leaves the search")
    func supersedeNeverEndsBeforeTheStart() async throws {
        try await withWorld { _, persistence, april in
            func fact(_ value: String, at date: Date) throws -> Fact {
                try Fact(
                    subjectID: april, predicate: "person.hobby", value: .string(value),
                    epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: date,
                    derivedFrom: [],
                    producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
                    origin: SourceID(validating: "mind:beaky"))
            }
            let newer = try fact("kites", at: left.addingTimeInterval(900))
            let older = try fact("stamps", at: left)
            try await persistence.facts.save(newer)
            try await persistence.facts.supersede(by: older)
            try await persistence.facts.save(older)

            let ended = try #require(try await persistence.facts.fact(withID: newer.factID))
            #expect(ended.validTo == newer.validFrom)
            #expect(ended.supersededBy == older.factID)
            let document = try #require(
                try await persistence.database[MongoWorldCollection.facts].findOne([
                    "_id": newer.factID.rawValue
                ]))
            #expect(document[FactRepository.searchTextField] == nil)

            // And the usual way round, a fact ends when the next one begins.
            let next = try fact("chess", at: left.addingTimeInterval(1_800))
            try await persistence.facts.supersede(by: next)
            #expect(
                try await persistence.facts.fact(withID: older.factID)?.validTo == next.validFrom)
        }
    }

    @Test("A fact already stored ending before it began is read, and does not fail its page")
    func storedBackwardsFactsAreRead() async throws {
        try await withWorld { _, persistence, april in
            func fact(_ value: String, at date: Date) throws -> Fact {
                try Fact(
                    subjectID: april, predicate: "person.hobby", value: .string(value),
                    epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: date,
                    derivedFrom: [],
                    producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
                    origin: SourceID(validating: "mind:beaky"))
            }
            let backwards = try fact("kites", at: left.addingTimeInterval(900))
            let by = try fact("stamps", at: left)
            try await persistence.facts.save(backwards)
            try await persistence.facts.save(by)
            // As the World stored it before 0.75.6.
            _ = try await persistence.database[MongoWorldCollection.facts].updateOne(
                where: ["_id": backwards.factID.rawValue],
                to: [
                    "$set": ["valid_to": left, "superseded_by": by.factID.rawValue] as Document
                ])

            let overwritten = try await persistence.facts.overwrittenFacts(
                originPrefix: "mind:", since: left.addingTimeInterval(-60), limit: 500
            ).filter { $0.replaced.subjectID == april }
            #expect(overwritten.map(\.replaced.factID) == [backwards.factID])
            #expect(overwritten.first?.replaced.validTo == backwards.validFrom)
        }
    }
}

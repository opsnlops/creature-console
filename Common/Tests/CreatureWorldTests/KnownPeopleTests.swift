import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

/// Who the words can name (#246): anyone the world can describe, not only those it knows a
/// relationship for.
@Suite(
    "Who the words can name, against MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct KnownPeopleTests {
    @Test("A person known by April's words or the address book is named, relationship or not")
    func everyoneDescribedIsKnown() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "known-people-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        // Names of letters alone: the words find a person by a whole word of their id.
        let letters = String(
            UUID().uuidString.lowercased().compactMap { $0.isLetter ? $0 : nil }.prefix(8))
        let polly = try EntityID(validating: "person:polly\(letters)")
        let quinn = try EntityID(validating: "person:quinn\(letters)")
        let jesse = try EntityID(validating: "person:jesse\(letters)")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        func fact(_ subject: EntityID, _ predicate: String, _ value: String) throws -> Fact {
            try Fact(
                subjectID: subject, predicate: predicate, value: .string(value),
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: now.addingTimeInterval(-3_600), derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        }
        for fact in [
            try fact(polly, WorldFacts.personDescription, "April's friend from flight school"),
            try fact(quinn, "contact.name", "Quinn Example"),
            try fact(jesse, WorldFacts.personRelationship, "General Contractor"),
            try fact(polly, "project.kite", "building a kite"),
        ] {
            try await persistence.facts.save(fact)
        }
        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)

        let known = try await knowledge.knownPeople(at: now)
        #expect(known.contains { $0.entityID == polly && $0.relationship == nil })
        #expect(known.contains { $0.entityID == quinn && $0.relationship == nil })
        #expect(known.contains { $0.entityID == jesse && $0.relationship == "General Contractor" })

        // "Who is Polly?" brings what the world knows of her, though it knows no relationship.
        let page = try await knowledge.page(
            about: [], mentionedIn: "Who is Polly\(letters)?",
            limit: WorldKnowledgeLimits.maximumFacts)
        let called = Set(page.calledUp)
        #expect(
            page.facts.contains {
                $0.subjectID == polly && $0.predicate == "project.kite"
                    && called.contains($0.factID)
            })
    }
}

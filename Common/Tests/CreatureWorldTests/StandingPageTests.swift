import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// The standing page against the real one, cap and all (#245): a name in the words used to take
/// places on a full page of thirty; now it sits beside them.
@Suite(
    "The standing page, against MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct StandingPageTests {
    @Test("A name the words bring never pushes a standing fact off the page")
    func namesSitBesideTheThirty() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "standing-page-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        // Names of letters alone: the words find a person by a whole word of their id.
        let letters = String(
            UUID().uuidString.lowercased().compactMap { $0.isLetter ? $0 : nil }.prefix(8))
        let bird = try EntityID(validating: "character:wren\(letters)")
        let april = try EntityID(validating: "person:april\(letters)")
        let jesse = try EntityID(validating: "person:jesse\(letters)")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        func fact(_ subject: EntityID, _ predicate: String, minutesAgo: Double) throws -> Fact {
            try Fact(
                subjectID: subject, predicate: predicate, value: .string("\(predicate) known"),
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: now.addingTimeInterval(-minutesAgo * 60), derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        }
        // A full page of what April told the bird, a day old; Jesse, told an hour ago.
        for n in 0..<WorldKnowledgeLimits.maximumFacts {
            try await persistence.facts.save(
                try fact(april, "taught.thing\(n)", minutesAgo: 1_440 + Double(n)))
        }
        // Known by what he is to April: the world names people in the words that way.
        for predicate in [WorldFacts.personRelationship, "project.deck", "visit.next"] {
            try await persistence.facts.save(try fact(jesse, predicate, minutesAgo: 60))
        }
        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        // Words that name Jesse and nobody else the test database holds.
        let words = "Jesse\(letters)?"
        let limit = WorldKnowledgeLimits.maximumFacts

        // Before: the newest thirty across everyone, so Jesse took three of April's places.
        let worded = try await knowledge.currentFacts(
            about: [bird, april], mentionedIn: words, limit: limit)
        let standing = try await knowledge.currentFacts(
            about: [bird, april], mentionedIn: nil, limit: limit)
        #expect(standing.filter { $0.subjectID == april }.count == limit)
        #expect(worded.filter { $0.subjectID == april }.count < limit)

        // Now: the whole standing page, byte for byte and first; Jesse beside it, called up.
        let page = try await knowledge.page(about: [bird, april], mentionedIn: words, limit: limit)
        #expect(Array(page.facts.prefix(standing.count)) == standing)
        let called = page.facts.filter { Set(page.calledUp).contains($0.factID) }
        #expect(
            Set(called.filter { $0.subjectID == jesse }.map(\.predicate)) == [
                WorldFacts.personRelationship, "project.deck", "visit.next",
            ])
        // None of April's: the words took no standing place.
        #expect(!called.contains { $0.subjectID == april })
        #expect(page.facts.count == standing.count + called.count)
    }
}

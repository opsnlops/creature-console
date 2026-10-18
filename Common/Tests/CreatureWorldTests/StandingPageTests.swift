import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

/// The page with words holds everything the words used to bring, and opens with the standing
/// page exactly (#245): what the words call up is gathered from what is new in them alone, so
/// this is the proof nothing they brought was lost. A memory filed on several subjects counts
/// once, by its name. `checking` narrows the proof to a test's own subjects, and is required: the
/// page also carries what the whole shared test database holds (the calendar near the test
/// clock, what the words search), which earlier runs and suites running alongside change
/// between two passes (#249).
func expectPageCovers(
    _ knowledge: PresentWorldKnowledge, about subjects: [EntityID], words: String,
    checking own: Set<EntityID>, sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let limit = WorldKnowledgeLimits.maximumFacts
    let page = try await knowledge.page(about: subjects, mentionedIn: words, limit: limit)
    let standing = try await knowledge.currentFacts(
        about: subjects, mentionedIn: nil, limit: limit)
    func mine(_ fact: Fact) -> Bool { own.contains(fact.subjectID) }
    // The standing part is the page with no words, and comes first: nothing called up sits
    // before a standing fact.
    let called = Set(page.calledUp)
    let kept = page.facts.filter { !called.contains($0.factID) }
    #expect(kept.filter(mine) == standing.filter(mine), sourceLocation: sourceLocation)
    #expect(
        page.facts.prefix(kept.count).allSatisfy { !called.contains($0.factID) },
        sourceLocation: sourceLocation)
    func key(_ fact: Fact) -> String {
        WorldFacts.memoryFamily(of: fact.predicate) != nil
            ? fact.predicate : "\(fact.subjectID.rawValue)|\(fact.predicate)|\(fact.value)"
    }
    let held = Set(page.facts.map(key))
    let worded = try await knowledge.currentFacts(
        about: subjects, mentionedIn: words, limit: limit)
    let lost = worded.filter { !held.contains(key($0)) && mine($0) }
    #expect(
        lost.isEmpty, "the page lost \(lost.map { "\($0.subjectID.rawValue) \($0.predicate)" })",
        sourceLocation: sourceLocation)
}

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

        // Now: the whole standing page, first; Jesse beside it, called up. The page also carries
        // what the whole shared test database holds (the calendar near this clock), which suites
        // running alongside change between two passes, so only this test's own are compared.
        let page = try await knowledge.page(about: [bird, april], mentionedIn: words, limit: limit)
        let calledUp = Set(page.calledUp)
        func mine(_ fact: Fact) -> Bool { [bird, april, jesse].contains(fact.subjectID) }
        let kept = page.facts.filter { !calledUp.contains($0.factID) }
        #expect(page.facts.prefix(kept.count).allSatisfy { !calledUp.contains($0.factID) })
        #expect(kept.filter(mine) == standing.filter(mine))
        let called = page.facts.filter { calledUp.contains($0.factID) }
        #expect(
            Set(called.filter { $0.subjectID == jesse }.map(\.predicate)) == [
                WorldFacts.personRelationship, "project.deck", "visit.next",
            ])
        // None of April's: the words took no standing place.
        #expect(!called.contains { $0.subjectID == april })
        #expect(page.facts.count == kept.count + called.count)
    }

    @Test("What comes and goes never pushes what the world was told off the page")
    func theMomentSitsBesideTheThirty() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "standing-page-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let letters = String(
            UUID().uuidString.lowercased().compactMap { $0.isLetter ? $0 : nil }.prefix(8))
        let bird = try EntityID(validating: "character:wren\(letters)")
        let april = try EntityID(validating: "person:april\(letters)")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        func fact(_ predicate: String, _ type: EpistemicType, minutesAgo: Double) throws -> Fact {
            try Fact(
                subjectID: april, predicate: predicate, value: .string("\(predicate) known"),
                epistemic: EpistemicState(type: type, confidence: 1),
                validFrom: now.addingTimeInterval(-minutesAgo * 60), derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        }
        let limit = WorldKnowledgeLimits.maximumFacts
        // A full page of what April told the birds, a day old.
        for n in 0..<limit {
            try await persistence.facts.save(
                try fact("taught.thing\(n)", .reported, minutesAgo: 1_440 + Double(n)))
        }
        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        func told() async throws -> [Fact] {
            try await knowledge.currentFacts(about: [bird, april], mentionedIn: nil, limit: limit)
                .filter { $0.subjectID == april && $0.epistemic.type == .reported }
        }
        let before = try await told()
        #expect(before.count == limit)
        // The moment arrives: a camera sighting, the last scene, motion - newer than all of it.
        let moment = ["seen.person", "scene.last", "motion.active", "door.lock", "media.tv"]
        for (n, predicate) in moment.enumerated() {
            try await persistence.facts.save(try fact(predicate, .observed, minutesAgo: Double(n)))
        }
        // Every told fact stays, so the cached layer does not move; the moment rides beside.
        #expect(try await told() == before)
        let page = try await knowledge.currentFacts(
            about: [bird, april], mentionedIn: nil, limit: limit)
        #expect(Set(page.filter { $0.epistemic.type == .observed }.map(\.predicate)) == Set(moment))
        // Newest first, together.
        let mine = page.filter { $0.subjectID == april }
        #expect(mine == mine.sorted { $0.validFrom > $1.validFrom })
    }

    @Test("A kind the words ask for comes up beside the standing page, never on it")
    func onRequestKindsAreCalledUp() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "standing-page-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let letters = String(
            UUID().uuidString.lowercased().compactMap { $0.isLetter ? $0 : nil }.prefix(8))
        let bird = try EntityID(validating: "character:wren\(letters)")
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let board = "body.board\(letters)_c"
        _ = try await persistence.factKinds.set(
            board, meaning: "the bird's board temperature", audience: nil, by: "test", at: now)
        try await persistence.facts.save(
            try Fact(
                subjectID: bird, predicate: board, value: .number(41),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: now.addingTimeInterval(-60), derivedFrom: [],
                producer: FactProducer(kind: "body", id: "sensors", version: "1")))
        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        let limit = WorldKnowledgeLimits.maximumFacts
        // Not asked for: a body is thirty lines a clock question does not need.
        let quiet = try await knowledge.page(
            about: [bird], mentionedIn: "what time is it?", limit: limit)
        #expect(!quiet.facts.contains { $0.predicate == board })
        // Asked for: called up, on the bird the page is about.
        let asked = try await knowledge.page(
            about: [bird], mentionedIn: "is your board warm?", limit: limit)
        let reading = try #require(asked.facts.first { $0.predicate == board })
        #expect(asked.calledUp.contains(reading.factID))
        try await expectPageCovers(
            knowledge, about: [bird], words: "is your board warm?", checking: [bird])
    }
}

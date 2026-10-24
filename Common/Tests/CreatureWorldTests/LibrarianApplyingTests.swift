import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

private let now = Date(timeIntervalSince1970: 1_789_600_000)

private func id(_ raw: String) -> EntityID { try! EntityID(validating: raw) }

private func kept(
    _ subject: EntityID, _ predicate: String, _ value: String, by origin: String = "mind:beaky",
    validTo: Date? = nil
) throws -> Fact {
    try Fact(
        subjectID: subject, predicate: predicate, value: .string(value),
        epistemic: EpistemicState(type: .reported, confidence: 1),
        validFrom: now.addingTimeInterval(-86_400), validTo: validTo, derivedFrom: [],
        producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
        origin: SourceID(validating: origin))
}

/// The night's `memory.filed`, as the agent records it.
private func filed(_ proposal: LibrarianProposal, subjects: [EntityID] = [id("character:beaky")])
    throws -> WorldEventEnvelope
{
    try WorldEventEnvelope(
        type: WorldEventType(validating: LibrarianFiling.filedEventType), occurredAt: now,
        source: EventSource(
            id: SourceID(validating: "mind:beaky"), kind: "mind",
            sourceEventID: "librarian:2026-10-15:\(UUID().uuidString)"),
        subjectIDs: subjects,
        epistemic: EpistemicState(type: .remembered, confidence: 1),
        payload: [
            "day": .string("2026-10-15"), "mode": .string("watching"),
            "proposal": try proposal.json,
        ])
}

/// #229, Ship 2: a night's filing is reviewed against the record as it is now, and applied
/// only where April checked it and it still stands.
@Suite("The librarian's filing, reviewed")
struct FilingReviewTests {
    private let april = id("person:april")

    @Test("A ready rewrite starts checked and ends at the earliest end of what it replaces")
    func readyRewriteCarriesTheEarliestExpiry() throws {
        let soon = now.addingTimeInterval(3_600)
        let later = now.addingTimeInterval(86_400)
        let a = try kept(
            april, "person.flight_training", "solos outside of landings", validTo: later)
        let b = try kept(april, "flight.hardest_part", "landings", validTo: soon)
        let c = try kept(april, "person.flight_rules", "flies VFR")
        let proposal = LibrarianProposal(rewrites: [
            .init(
                subject: april, predicate: "flight.training",
                value: "Solos outside of landings, the hardest part; flies VFR.",
                replaces: [a.factID, b.factID, c.factID], reason: "one topic")
        ])
        let item = try #require(
            FilingReviewer(
                proposal: proposal,
                record: .init(facts: [a.factID: a, b.factID: b, c.factID: c], now: now)
            ).items.first)
        #expect(item.status == .ready)
        #expect(item.checked)
        #expect(item.validTo == soon)
    }

    @Test("A rewrite whose fact a bird has since kept again is stale, and never checked")
    func newerKeepingMakesItStale() throws {
        var old = try kept(april, "flight.hope", "hopes to fly to the islands")
        old.supersededBy = FactID.generated()
        let gone = FactID.generated()
        let proposal = LibrarianProposal(
            rewrites: [
                .init(
                    subject: april, predicate: "flight.hope", value: "x", replaces: [old.factID],
                    reason: "")
            ],
            retires: [.init(fact: gone, reason: "old news")])
        let items = FilingReviewer(
            proposal: proposal, record: .init(facts: [old.factID: old], now: now)
        ).items
        #expect(items.map(\.status) == [.stale, .stale])
        #expect(items.allSatisfy { !$0.checked })
        #expect(items[1].reason?.contains("no longer in the record") == true)
    }

    @Test("A rewrite onto a name that holds a fact it does not fold in is guarded")
    func rewriteNeverWritesOverWhatItLeavesOut() throws {
        let held = try kept(april, "flight.training", "learning crosswind landings")
        let other = try kept(april, "person.flight_training", "solos")
        let proposal = LibrarianProposal(rewrites: [
            .init(
                subject: april, predicate: "flight.training", value: "Solos.",
                replaces: [other.factID], reason: "")
        ])
        let item = FilingReviewer(
            proposal: proposal,
            record: .init(facts: [other.factID: other], held: [april: [held, other]], now: now)
        ).items.first
        #expect(item?.status == .guarded)
        #expect(item?.reason?.contains("does not fold in") == true)
    }

    @Test("An expired fact is stale too: a plan whose day is past")
    func expiredFactIsStale() throws {
        let plan = try kept(
            april, "person.schedule", "gym today", validTo: now.addingTimeInterval(-60))
        let proposal = LibrarianProposal(retires: [.init(fact: plan.factID, reason: "past")])
        #expect(
            FilingReviewer(proposal: proposal, record: .init(facts: [plan.factID: plan], now: now))
                .items.first?.status == .stale)
    }

    @Test("Visitors, presence, sightings, and pronouns are guarded, whichever side they are on")
    func protectedKindsAreGuarded() throws {
        let cleaner = id("thing:cleaner-test")
        let visits = try (0..<3).map {
            try kept(cleaner, "visitor.expected", "arrives around ten, visit \($0)")
        }
        let sighting = try kept(id("place:carport"), "sighting.identified", "April")
        let proposal = LibrarianProposal(
            rewrites: [
                .init(
                    subject: cleaner, predicate: "cleaning.schedule", value: "around ten",
                    replaces: visits.map(\.factID), reason: "")
            ],
            retires: [.init(fact: sighting.factID, reason: "")],
            kinds: [.init(predicate: "presence.mood", meaning: "x")])
        var facts = Dictionary(uniqueKeysWithValues: visits.map { ($0.factID, $0) })
        facts[sighting.factID] = sighting
        let items = FilingReviewer(proposal: proposal, record: .init(facts: facts, now: now))
            .items
        #expect(items.map(\.status) == [.guarded, .guarded, .guarded])
        #expect(items[0].reason?.contains("visitor.expected") == true)
    }

    @Test("A kind already meant keeps its meaning; a new one is written")
    func kindsAlreadyMeantAreGuarded() {
        let proposal = LibrarianProposal(kinds: [
            .init(predicate: "flight.training", meaning: "new words"),
            .init(predicate: "religion.background", meaning: "the person's religious history"),
        ])
        let items = FilingReviewer(
            proposal: proposal, record: .init(meant: ["flight.training"], now: now)
        ).items
        #expect(items.map(\.status) == [.guarded, .ready])
    }

    @Test("A sure merge starts checked, an unsure one doesn't; what the kept id holds stays")
    func mergesMoveWhatTheKeptIdDoesNotHold() throws {
        let keep = id("place:new-workshop-test")
        let other = id("thing:new-workshop-test")
        let held = try kept(keep, "workshop.size", "1,100 square feet")
        let clash = try kept(other, "workshop.size", "about a thousand square feet")
        let moving = try kept(other, "workshop.tiki_room", "the birds will hang from the roof")
        let memory = try kept(other, "memory.episode.beaky.2026-10-16.1", "April told us")
        let proposal = LibrarianProposal(same: [
            .init(ids: [keep, other], keep: keep, sure: true, reason: "same building"),
            .init(
                ids: [id("person:amber-test"), id("thing:cleaner-two")],
                keep: id("person:amber-test"), sure: false, reason: "a role alone"),
        ])
        let items = FilingReviewer(
            proposal: proposal,
            record: .init(kept: [keep: [held], other: [clash, moving, memory]], now: now)
        ).items
        #expect(items[0].status == .ready)
        #expect(items[0].checked)
        #expect(items[0].moves == [moving.factID])
        #expect(items[0].stays == [clash.factID])
        #expect(items[1].status == .ready)
        #expect(!items[1].checked)
    }

    @Test("Birds are never merged, and an id already merged is not merged again")
    func birdsAndMergedIdsAreGuarded() {
        let proposal = LibrarianProposal(same: [
            .init(
                ids: [id("character:kenny"), id("thing:kenny-test")], keep: id("character:kenny"),
                sure: true, reason: ""),
            .init(
                ids: [id("place:workshop-test"), id("thing:old-barn-test")],
                keep: id("place:workshop-test"), sure: true, reason: ""),
        ])
        let items = FilingReviewer(
            proposal: proposal,
            record: .init(sameAs: [id("thing:old-barn-test"): id("place:pole-barn-test")], now: now)
        ).items
        #expect(items.map(\.status) == [.guarded, .guarded])
    }

    @Test("A rename moves everything on the misfiled id, memories too; a person stays a person")
    func renamesReview() throws {
        let taco = id("person:rocket-taco-test")
        let place = id("place:rocket-taco-test")
        let memory = try kept(taco, "memory.belief.caroll.1", "April often eats there")
        var card = try kept(id("person:sarah-test"), "contact.phone_kind", "mobile")
        card.origin = try SourceID(validating: "bridge:contacts")
        let proposal = LibrarianProposal(renames: [
            .init(id: taco, to: place, reason: "a taco restaurant"),
            .init(id: card.subjectID, to: id("place:sarah-test"), reason: "wrong"),
            .init(id: id("character:kenny"), to: id("thing:kenny"), reason: "wrong"),
        ])
        let items = FilingReviewer(
            proposal: proposal,
            record: .init(held: [taco: [memory], card.subjectID: [card]], now: now)
        ).items
        #expect(items.map(\.status) == [.ready, .guarded, .guarded])
        #expect(items[0].checked)
        #expect(items[0].moves == [memory.factID])
        #expect(items[1].reason?.contains("address book") == true)
    }

    @Test("What was applied before reads as applied")
    func appliedItemsReadAsApplied() {
        let proposal = LibrarianProposal(kinds: [.init(predicate: "gym.routine", meaning: "x")])
        let item = FilingReviewer(
            proposal: proposal, record: .init(applied: [FilingItemKey(.kinds, 0)], now: now)
        ).items.first
        #expect(item?.status == .applied)
        #expect(item?.checked == false)
    }

    @Test("The proposal reads back from the event the agent records")
    func proposalRoundTripsThroughTheFiledEvent() throws {
        let proposal = LibrarianProposal(
            rewrites: [
                .init(
                    subject: april, predicate: "flight.rules", value: "flies VFR",
                    replaces: [FactID.generated()], reason: "file beside the others")
            ],
            questions: ["Has the lesson plane come back?"], dropped: 2)
        let event = try filed(proposal)
        #expect(LibrarianProposal(filed: event) == proposal)
        // The wire shape Ship 1 recorded, field for field.
        guard case .object(let fields)? = event.payload["proposal"],
            case .array(let rewrites)? = fields["rewrites"],
            case .object(let first)? = rewrites.first
        else {
            Issue.record("no proposal object")
            return
        }
        #expect(Set(first.keys) == ["subject", "predicate", "value", "replaces", "reason"])
        #expect(fields["dropped"] == .number(2))
    }

    @Test("A selection lists each checked item once, in order")
    func selectionKeysAreUniqueAndOrdered() throws {
        let selection = try JSONDecoder().decode(
            FilingSelection.self, from: Data(#"{"same": [1], "rewrites": [3, 0, 3]}"#.utf8))
        #expect(
            selection.keys == [
                FilingItemKey(.rewrites, 0), FilingItemKey(.rewrites, 3), FilingItemKey(.same, 1),
            ])
    }
}

@Suite("The librarian's filing, reduced")
struct FilingReducerTests {
    @Test("A rewrite is one fact derived from what it replaces; the other names end")
    func rewriteEndsTheOtherNames() throws {
        let april = id("person:april")
        let a = try kept(april, "person.flight_training", "solos")
        let b = try kept(april, "flight.training", "learning to land")
        let application = FilingApplication(
            filing: EventID.generated(), items: [FilingItemKey(.rewrites, 0)],
            rewrites: [
                .init(
                    subjectID: april, predicate: "flight.training",
                    value: "Solos; learning to land.", validTo: nil,
                    replaces: [.init(a), .init(b)])
            ])
        let event = try WorldEventEnvelope(
            occurredAt: now,
            source: EventSource(id: SourceID(validating: "librarian:beaky"), kind: "librarian"),
            subjectIDs: application.subjects,
            epistemic: EpistemicState(type: .reported, confidence: 1), payload: application)
        let facts = try FilingReducer().reduce(event).changedFacts
        // One ending (the other name), one new fact; the same name is simply superseded.
        #expect(facts.count == 2)
        #expect(facts[0].predicate == "person.flight_training")
        #expect(facts[0].value == .null)
        let filed = facts[1]
        #expect(filed.value == .string("Solos; learning to land."))
        #expect(filed.origin == (try SourceID(validating: "librarian:beaky")))
        #expect(filed.derivedFrom == [.event(event.eventID), .fact(a.factID), .fact(b.factID)])
    }

    @Test("A filed fact is as old as the newest of what it replaces, never the click")
    func filedFactKeepsItsAge() throws {
        let april = id("person:april")
        let older = now.addingTimeInterval(-30 * 86_400)
        let newer = now.addingTimeInterval(-2 * 86_400)
        let event = try WorldEventEnvelope(
            occurredAt: now,
            source: EventSource(id: SourceID(validating: "librarian:beaky"), kind: "librarian"),
            subjectIDs: [april], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: FilingApplication(
                filing: EventID.generated(), items: [FilingItemKey(.rewrites, 0)],
                rewrites: [
                    .init(
                        subjectID: april, predicate: "flight.rules", value: "Flies VFR.",
                        validFrom: newer, validTo: nil,
                        replaces: [.init(try kept(april, "person.flight_rules", "VFR"))])
                ]))
        let filed = try #require(
            try FilingReducer().reduce(event).changedFacts.first { $0.value != .null })
        #expect(filed.validFrom == newer)
        #expect(filed.validFrom > older)
        // An application recorded before the date was carried begins at its own moment.
        #expect(FilingReducer.start(nil, by: event) == now)
        #expect(FilingReducer.start(now.addingTimeInterval(60), by: event) == now)
    }

    @Test("A merge marks the merged id and moves its facts to the kept one")
    func mergeMarksAndMoves() throws {
        let keep = id("place:new-workshop")
        let other = id("thing:new-workshop")
        let moving = try kept(other, "workshop.tiki_room", "the birds hang from the roof")
        let application = FilingApplication(
            filing: EventID.generated(), items: [FilingItemKey(.same, 0)],
            merges: [.init(merged: [other], keep: keep, moves: [.init(moving)])])
        let event = try WorldEventEnvelope(
            occurredAt: now,
            source: EventSource(id: SourceID(validating: "librarian:beaky"), kind: "librarian"),
            subjectIDs: application.subjects,
            epistemic: EpistemicState(type: .reported, confidence: 1), payload: application)
        let facts = try FilingReducer().reduce(event).changedFacts
        #expect(facts.count == 3)
        #expect(facts[0].subjectID == other)
        #expect(facts[0].predicate == WorldFacts.entitySameAs)
        #expect(facts[0].value == .string(keep.rawValue))
        #expect(facts[1].subjectID == other && facts[1].value == .null)
        #expect(facts[2].subjectID == keep && facts[2].predicate == "workshop.tiki_room")
        #expect(facts[2].derivedFrom.contains(.fact(moving.factID)))
    }

    @Test("A fact learned in a whisper keeps its bird when a merge moves it (#263)")
    func mergeKeepsAWhisper() throws {
        let keep = id("place:new-workshop")
        let other = id("thing:new-workshop")
        var moving = try kept(other, "workshop.secret", "only Beaky was told")
        moving.aloneWith = id("character:beaky")
        let application = FilingApplication(
            filing: EventID.generated(), items: [FilingItemKey(.same, 0)],
            merges: [.init(merged: [other], keep: keep, moves: [.init(moving)])])
        let event = try WorldEventEnvelope(
            occurredAt: now,
            source: EventSource(id: SourceID(validating: "librarian:beaky"), kind: "librarian"),
            subjectIDs: application.subjects,
            epistemic: EpistemicState(type: .reported, confidence: 1), payload: application)
        // Through the wire as the World keeps it, then reduced.
        let decoded = try WorldJSON.makeDecoder().decode(
            FilingApplication.self, from: WorldJSON.makeEncoder().encode(application))
        #expect(decoded.merges.first?.moves.first?.aloneWith == id("character:beaky"))
        let moved = try FilingReducer().reduce(event).changedFacts.last
        #expect(moved?.subjectID == keep)
        #expect(moved?.aloneWith == id("character:beaky"))
    }
}

@Suite(
    "The librarian's filing, applied in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct FilingApplyMongoTests {
    private struct Harness {
        let persistence: MongoWorldPersistence
        let world: World
        let desk: FilingDesk
        let clock: ManualWorldClock

        func keep(
            _ subject: EntityID, _ predicate: String, _ value: String, by mind: String,
            kind: String = "mind"
        ) async throws {
            let event = try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: await clock.now,
                source: EventSource(
                    id: SourceID(validating: mind), kind: kind,
                    sourceEventID: UUID().uuidString),
                subjectIDs: [subject],
                epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(subject.rawValue), "predicate": .string(predicate),
                    "value": .string(value),
                ])
            // The door, as the World wires it: the world's own refused, then the redirect.
            _ = try await world.accept(try await desk.redirect(try await desk.check(event)))
        }

        /// The value a name holds now; an ending (`null`, gone a second later) holds none.
        func current(_ subject: EntityID, _ predicate: String) async throws -> Fact? {
            try await persistence.facts.currentFacts(subjectID: subject, at: await clock.now)
                .first { $0.predicate == predicate && $0.value != .null }
        }
    }

    private func harness() async throws -> Harness {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "filing-tests"))
        let clock = ManualWorldClock(now: now)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GivenFactReducer(), FilingReducer()], clock: clock)
        let desk = FilingDesk(
            events: persistence.events, facts: persistence.facts, kinds: persistence.factKinds,
            accept: { try await world.accept($0) }, clock: clock)
        return Harness(persistence: persistence, world: world, desk: desk, clock: clock)
    }

    @Test("A checked rewrite is filed by the librarian; the facts it replaced leave the record")
    func rewriteIsFiled() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let april = id("person:april-\(UUID().uuidString.lowercased())")
        try await h.keep(
            april, "person.flight_training", "solos outside of landings", by: "mind:mango")
        try await h.keep(april, "flight.hardest_part", "landings", by: "mind:beaky")
        let a = try #require(try await h.current(april, "person.flight_training"))
        let b = try #require(try await h.current(april, "flight.hardest_part"))
        let filing = try filed(
            LibrarianProposal(
                rewrites: [
                    .init(
                        subject: april, predicate: "flight.training",
                        value: "Solos outside of landings, which are the hardest part.",
                        replaces: [a.factID, b.factID], reason: "one topic")
                ],
                kinds: [
                    .init(
                        predicate: "flight.training-\(UUID().uuidString.lowercased())", meaning: "x"
                    )
                ]),
            subjects: [april])
        _ = try await h.world.accept(filing)

        let review = try #require(try await h.desk.review(filing.eventID))
        #expect(review.items.map(\.status) == [.ready, .ready])
        #expect(Set(review.facts.map(\.factID)) == [a.factID, b.factID])

        let result = try #require(
            try await h.desk.apply(filing.eventID, FilingSelection(rewrites: [0], kinds: [0])))
        #expect(result.outcomes.allSatisfy { $0.applied })
        let filed = try #require(try await h.current(april, "flight.training"))
        #expect(filed.origin == (try SourceID(validating: "librarian:beaky")))
        #expect(filed.derivedFrom.contains(.fact(a.factID)))
        #expect(try await h.current(april, "person.flight_training") == nil)
        #expect(try await h.current(april, "flight.hardest_part") == nil)
        let kind = review.proposal.kinds[0].predicate
        #expect(try await h.persistence.factKinds.meanings(of: [kind])[kind] == "x")

        // Again: nothing more happens, and the review says it was done.
        let again = try #require(
            try await h.desk.apply(filing.eventID, FilingSelection(rewrites: [0], kinds: [0])))
        #expect(again.outcomes.allSatisfy { !$0.applied })
        #expect(again.event == nil)
        #expect(
            try await h.desk.review(filing.eventID)?.items.map(\.status) == [.applied, .applied])
    }

    @Test("What a bird keeps between review and apply wins: the item is skipped")
    func staleAtApplyIsSkipped() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let april = id("person:april-\(UUID().uuidString.lowercased())")
        try await h.keep(
            april, "flight.return_hope", "back by the end of the month", by: "mind:beaky")
        let hope = try #require(try await h.current(april, "flight.return_hope"))
        let filing = try filed(
            LibrarianProposal(retires: [.init(fact: hope.factID, reason: "old news")]),
            subjects: [april])
        _ = try await h.world.accept(filing)
        #expect(try await h.desk.review(filing.eventID)?.items.first?.status == .ready)

        try await h.clock.advance(by: 60)
        try await h.keep(april, "flight.return_hope", "back next week", by: "mind:caroll")
        let result = try #require(
            try await h.desk.apply(filing.eventID, FilingSelection(retires: [0])))
        #expect(result.outcomes.first?.applied == false)
        #expect(result.outcomes.first?.reason?.contains("changed since the night") == true)
        #expect(
            try await h.current(april, "flight.return_hope")?.value == .string("back next week"))
    }

    @Test("A mind never keeps the world's own kinds; anyone else may, and a bird keeps the rest")
    func mindsNeverKeepTheWorldsOwn() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let room = id("place:tiki-room-\(suffix)")
        let letters = String(suffix.compactMap { $0.isLetter ? $0 : nil }.prefix(8))
        let card = "contact.number_\(letters)"
        _ = try await h.persistence.factKinds.set(
            card, meaning: "a phone number from the card", audience: .world, by: "test",
            at: now)
        // "These two are the same thing": the merge is the librarian's, with April's check.
        for (predicate, value) in [
            (WorldFacts.entitySameAs, "place:new-workshop-\(suffix)"),
            (WorldFacts.locationGPS, "48.0, -122.5"), (WorldFacts.placeGeo, "40.0, -100.0"),
            (card, "555-0100"),
        ] {
            await #expect(throws: WorldContractError.self) {
                try await h.keep(room, predicate, value, by: "mind:beaky")
            }
            #expect(try await h.current(room, predicate) == nil)
        }
        try await h.keep(room, "workshop.perches", "hung from the roof", by: "mind:beaky")
        #expect(
            try await h.current(room, "workshop.perches")?.value == .string("hung from the roof"))
        // A Wizard is not a mind.
        try await h.keep(
            room, WorldFacts.entitySameAs, "place:new-workshop-\(suffix)", by: "wizard:april",
            kind: "person")
        #expect(try await h.current(room, WorldFacts.entitySameAs) != nil)
    }

    @Test("A merge moves what the kept id lacks, and a later keeping on the old id lands on it")
    func mergeMovesAndRedirects() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let keep = id("place:new-workshop-\(suffix)")
        let other = id("thing:new-workshop-\(suffix)")
        try await h.keep(keep, "workshop.size", "1,100 square feet", by: "mind:beaky")
        try await h.keep(other, "workshop.size", "big", by: "mind:mango")
        try await h.keep(
            other, "workshop.tiki_room", "the birds hang from the roof", by: "mind:beaky")
        let filing = try filed(
            LibrarianProposal(same: [
                .init(ids: [keep, other], keep: keep, sure: true, reason: "one building")
            ]),
            subjects: [keep, other])
        _ = try await h.world.accept(filing)
        let item = try #require(try await h.desk.review(filing.eventID)?.items.first)
        #expect(item.moves.count == 1)
        #expect(item.stays.count == 1)

        let result = try #require(
            try await h.desk.apply(filing.eventID, FilingSelection(same: [0])))
        #expect(result.outcomes.first?.applied == true)
        #expect(
            try await h.current(other, WorldFacts.entitySameAs)?.value == .string(keep.rawValue))
        #expect(
            try await h.current(keep, "workshop.tiki_room")?.value
                == .string("the birds hang from the roof"))
        #expect(try await h.current(other, "workshop.tiki_room") == nil)
        // The clash stays where it was: two values for one name is April's question.
        #expect(try await h.current(other, "workshop.size")?.value == .string("big"))
        #expect(try await h.current(keep, "workshop.size")?.value == .string("1,100 square feet"))

        try await h.clock.advance(by: 60)
        try await h.keep(
            other, "workshop.fiber", "fiber is being pulled out there", by: "mind:kenny")
        #expect(try await h.current(other, "workshop.fiber") == nil)
        #expect(
            try await h.current(keep, "workshop.fiber")?.value
                == .string("fiber is being pulled out there"))
    }

    @Test("Facts filed before dates were carried are dated by what they came from")
    func repairDatesFiledFacts() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let april = id("person:april-\(UUID().uuidString.lowercased())")
        try await h.keep(april, "person.flight_rules", "flies VFR", by: "mind:beaky")
        let source = try #require(try await h.current(april, "person.flight_rules"))
        try await h.clock.advance(by: 86_400)
        // As 0.52.0 filed it: begun at the moment of applying.
        let undated = try Fact(
            subjectID: april, predicate: "flight.rules", value: .string("Flies VFR."),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: await h.clock.now,
            derivedFrom: [.event(EventID.generated()), .fact(source.factID)],
            producer: FilingReducer.producer, origin: SourceID(validating: "librarian:beaky"))
        try await h.persistence.facts.save(undated)
        _ = try await h.persistence.facts.dateFiledFacts()
        let dated = try #require(try await h.persistence.facts.fact(withID: undated.factID))
        #expect(dated.validFrom == source.validFrom)
    }

    @Test("A rename files the memories on the right kind, and the nightly re-filing follows")
    func renameMovesMemoriesAndRedirects() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let taco = id("person:rocket-taco-\(suffix)")
        let place = id("place:rocket-taco-\(suffix)")
        try await h.keep(
            taco, "memory.belief.caroll.1", "April often eats at Rocket Taco", by: "mind:caroll")
        let candidates = try await h.desk.kindCandidates().candidates
        #expect(
            candidates.contains { $0.id == taco && $0.said == ["April often eats at Rocket Taco"] })

        let filing = try filed(
            LibrarianProposal(renames: [.init(id: taco, to: place, reason: "a taco restaurant")]),
            subjects: [taco])
        _ = try await h.world.accept(filing)
        let result = try #require(
            try await h.desk.apply(filing.eventID, FilingSelection(renames: [0])))
        #expect(result.outcomes.first?.applied == true)
        #expect(
            try await h.current(place, "memory.belief.caroll.1")?.value
                == .string("April often eats at Rocket Taco"))
        #expect(try await h.current(taco, "memory.belief.caroll.1") == nil)
        #expect(
            try await h.current(taco, WorldFacts.entitySameAs)?.value == .string(place.rawValue))
        // Merged away, it is no longer a candidate.
        #expect(try await !h.desk.kindCandidates().candidates.contains { $0.id == taco })

        // Tomorrow night Caroll believes it again, under the old id: it lands on the place.
        try await h.clock.advance(by: 86_400)
        try await h.keep(
            taco, "memory.belief.caroll.1", "April usually orders chicken there", by: "mind:caroll")
        #expect(
            try await h.current(place, "memory.belief.caroll.1")?.value
                == .string("April usually orders chicken there"))
    }

    @Test("The page holds the filed fact once, kept by the librarian, and not what it replaced")
    func pageHoldsTheFiledFact() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let april = id("person:april-\(UUID().uuidString.lowercased())")
        try await h.keep(
            april, "person.flight_training", "flies on her own outside of landings",
            by: "mind:mango")
        try await h.keep(april, "flight.hardest_part", "landings", by: "mind:beaky")
        try await h.keep(april, "person.flight_rules", "flies VFR", by: "mind:beaky")
        let replaced = try await [
            "person.flight_training", "flight.hardest_part", "person.flight_rules",
        ].asyncMap { try #require(try await h.current(april, $0)) }
        let filing = try filed(
            LibrarianProposal(rewrites: [
                .init(
                    subject: april, predicate: "flight.training",
                    value: "Flies on her own outside of landings, the hardest part, under VFR.",
                    replaces: replaced.map(\.factID), reason: "one topic")
            ]),
            subjects: [april])
        _ = try await h.world.accept(filing)
        _ = try await h.desk.apply(filing.eventID, FilingSelection(rewrites: [0]))
        // Past the endings' second.
        try await h.clock.advance(by: 2)

        let knowledge = PresentWorldKnowledge(
            facts: h.persistence.facts, events: h.persistence.events,
            kinds: h.persistence.factKinds,
            sessions: CharacterSessionService(
                repository: h.persistence.characterSessions, clock: h.clock, announce: { _ in }),
            regions: [:], clock: h.clock)
        let page = try await knowledge.currentFacts(
            about: [april], mentionedIn: "landings are still the hardest part of flying",
            limit: WorldKnowledgeLimits.maximumFacts
        ).filter { $0.subjectID == april }
        try await expectPageCovers(
            knowledge, about: [april], words: "landings are still the hardest part of flying",
            checking: [april])
        #expect(page.filter { $0.predicate == "flight.training" }.count == 1)
        #expect(
            page.first { $0.predicate == "flight.training" }?.origin?.rawValue == "librarian:beaky")
        #expect(
            !page.contains {
                ["person.flight_training", "flight.hardest_part", "person.flight_rules"].contains(
                    $0.predicate)
            })
    }
}

extension Array {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for element in self { out.append(try await transform(element)) }
        return out
    }
}

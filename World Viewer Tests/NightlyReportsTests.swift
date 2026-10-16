import Foundation
import Testing
import WorldCore

@testable import World_Viewer

/// Shapes as the world holds them (sampled from production, 2026-10-01): a reflection is
/// `{day, text}` on the bird; an episode is `{day, salience, what, when}`, filed once per subject
/// it is about. The words are made up.
@Suite("The nightly reports, by night")
struct NightlyReportsTests {
    private func fact(_ subject: String, _ predicate: String, _ value: WorldJSONValue) throws
        -> Fact
    {
        try Fact(
            subjectID: EntityID(validating: subject), predicate: predicate, value: value,
            epistemic: EpistemicState(type: .remembered, confidence: 0.9),
            validFrom: Date(timeIntervalSince1970: 1_790_000_000), derivedFrom: [],
            producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
    }

    private func reflection(_ bird: String, _ day: String, _ text: String) throws -> Fact {
        try fact(
            "character:\(bird)", "memory.reflection.\(bird).\(day)",
            .object(["day": .string(day), "text": .string(text)]))
    }

    private func episode(
        _ subject: String, _ bird: String, _ day: String, _ n: Int, _ what: String,
        salience: Double
    ) throws -> Fact {
        try fact(
            subject, "memory.episode.\(bird).\(day).\(n)",
            .object([
                "day": .string(day), "salience": .number(salience), "what": .string(what),
                "when": .string("Wednesday evening"),
            ]))
    }

    @Test("Nights come from the reflections, newest first, with the birds that wrote one")
    func nightsFromReflections() throws {
        let nights = NightlyReports.nights(fromReflections: [
            try reflection("kenny", "2026-09-29", "A good day."),
            try reflection("beaky", "2026-09-30", "April, the kettle sang."),
            try reflection("kenny", "2026-09-30", "Kenny helped."),
            // A retracted reflection is no night.
            try fact("character:mango", "memory.reflection.mango.2026-09-28", .null),
        ])
        #expect(nights.map(\.day) == ["2026-09-30", "2026-09-29"])
        #expect(nights[0].birds == ["beaky", "kenny"])
    }

    @Test("A night: each bird's letter, its episodes once each, most salient first")
    func oneNight() throws {
        let day = "2026-09-30"
        let reflections = [
            try reflection("kenny", day, "Kenny helped."),
            try reflection("kenny", "2026-09-29", "Another night."),
        ]
        let episodes = [
            // One episode, filed on two subjects: shown once, about both.
            try episode("person:april", "kenny", day, 1, "The kettle sang.", salience: 0.4),
            try episode("place:kitchen", "kenny", day, 1, "The kettle sang.", salience: 0.4),
            try episode("person:april", "kenny", day, 2, "A screw went missing.", salience: 0.9),
            // Another night's and another bird's are not this report's Kenny.
            try episode("person:april", "kenny", "2026-09-29", 1, "Old news.", salience: 1),
            try episode("person:april", "mango", day, 1, "A database joke.", salience: 0.5),
        ]
        let report = NightlyReports.report(day: day, reflections: reflections, episodes: episodes)
        #expect(report.map(\.bird) == ["kenny", "mango"])
        let kenny = try #require(report.first)
        #expect(kenny.reflectionText == "Kenny helped.")
        #expect(kenny.episodes.map(\.what) == ["A screw went missing.", "The kettle sang."])
        #expect(kenny.episodes[1].about.map(\.rawValue) == ["person:april", "place:kitchen"])
        #expect(kenny.episodes[1].when == "Wednesday evening")
        // A bird with episodes but no letter still has its night.
        #expect(report[1].reflectionText == nil)
        #expect(report[1].episodes.count == 1)
    }

    @Test("The day in a memory predicate, and nothing from other predicates")
    func dayOfPredicate() {
        #expect(NightlyReports.day(of: "memory.episode.kenny.2026-09-30.3") == "2026-09-30")
        #expect(NightlyReports.day(of: "memory.reflection.beaky.2026-09-20") == "2026-09-20")
        #expect(NightlyReports.day(of: "memory.belief.beaky.2") == nil)
        #expect(NightlyReports.day(of: "presence.state") == nil)
        #expect(NightlyPanel.title(of: "2026-09-30") == "Wednesday, September 30")
    }
}

/// The librarian's night as the Viewer reads it (#229): the `memory.filed` event's proposal.
@Suite("The librarian's night")
struct FilingTests {
    @Test(
        "A filing reads its rewrites, retires, sames, kinds, and questions; watching unless applied"
    )
    func readsAFiling() throws {
        let event = try WorldEventEnvelope(
            type: WorldEventType(validating: "memory.filed"),
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            source: EventSource(
                id: SourceID(validating: "mind:beaky"), kind: "mind",
                sourceEventID: "librarian:2026-10-14:run"),
            subjectIDs: [EntityID(validating: "character:beaky")],
            epistemic: EpistemicState(type: .remembered, confidence: 1),
            payload: [
                "day": .string("2026-10-14"), "mode": .string("watching"),
                "learned": .number(120), "overwritten": .number(1),
                "proposal": .object([
                    "rewrites": .array([
                        .object([
                            "subject": .string("person:april"),
                            "predicate": .string("flight.training"),
                            "value": .string("flies on her own but for landings"),
                            "replaces": .array([.string("fact:a"), .string("fact:b")]),
                            "reason": .string("one topic, one name"),
                        ])
                    ]),
                    "retires": .array([
                        .object(["fact": .string("fact:c"), "reason": .string("old news")])
                    ]),
                    "same": .array([
                        .object([
                            "ids": .array([.string("thing:a"), .string("thing:b")]),
                            "keep": .string("thing:a"), "sure": .bool(false),
                            "reason": .string("both a flight school"),
                        ])
                    ]),
                    "kinds": .array([
                        .object([
                            "predicate": .string("flight.training"),
                            "meaning": .string("where April is in learning to fly"),
                        ])
                    ]),
                    "questions": .array([.string("Is Amber Tamara?")]),
                    "dropped": .number(2),
                ]),
            ])
        let filing = try #require(NightlyReports.filing(from: event))
        #expect(filing.day == "2026-10-14")
        #expect(filing.bird == "beaky")
        #expect(filing.watching)
        #expect(filing.learned == 120)
        #expect(filing.rewrites.first?.replaces == 2)
        #expect(filing.retires.first?.reason == "old news")
        #expect(filing.same.first?.what == "thing:a = thing:b, keep thing:a (not sure: a question)")
        #expect(filing.kinds.first?.what == "flight.training")
        #expect(filing.questions == ["Is Amber Tamara?"])
        #expect(filing.dropped == 2)
        #expect(!filing.isEmpty)
    }

    @Test("A fact says who kept it: a bird, the librarian, or a source")
    func keptBy() throws {
        func fact(_ origin: String?) throws -> Fact {
            try Fact(
                subjectID: EntityID(validating: "person:april"), predicate: "flight.hope",
                value: .string("a plane"),
                epistemic: EpistemicState(type: .reported, confidence: 1),
                validFrom: Date(timeIntervalSince1970: 1_790_000_000), derivedFrom: [],
                producer: FactProducer(kind: "presence", id: "given-facts", version: "1"),
                origin: try origin.map { try SourceID(validating: $0) })
        }
        #expect(try fact("mind:mango").keptBy == "kept by Mango")
        #expect(try fact("librarian:beaky").keptBy == "filed by Beaky, the librarian")
        #expect(try fact("bridge:contacts").keptBy == "from bridge:contacts")
        #expect(try fact(nil).keptBy == nil)
    }
}

/// The Page (#231): a bird's page sorted by what each fact is.
@Suite("A bird's page, by what it holds")
struct FactPageSectionsTests {
    private func fact(
        _ subject: String, _ predicate: String, origin: String? = nil,
        producer: FactProducer = FactProducer(kind: "presence", id: "given-facts", version: "1")
    ) throws -> Fact {
        try Fact(
            subjectID: EntityID(validating: subject), predicate: predicate, value: .string("x"),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_790_000_000), derivedFrom: [],
            producer: producer, origin: try origin.map { try SourceID(validating: $0) })
    }

    @Test("Learned, state, folded, calendar, memories, and stage, counted")
    func sortsThePage() throws {
        let sections = FactPageSections(facts: [
            try fact("person:april", "flight.training", origin: "mind:beaky"),
            try fact("person:april", "flight.rules", origin: "librarian:beaky"),
            try fact("place:front-door", "door.lock", origin: "home-assistant:lock-front-door"),
            try fact(
                "place:outside", "environment.now",
                producer: FactProducer(kind: "world", id: "page", version: "1")),
            try fact("event:abc-20261018", "calendar.title", origin: "bridge:calendar"),
            try fact("person:april", "memory.episode.beaky.2026-10-14.1", origin: "mind:beaky"),
            try fact("character:mango", "presence.region"),
            try fact("character:mango", "identity.pronouns"),
        ])
        #expect(sections.facts(of: .learned).count == 2)
        #expect(sections.facts(of: .state).count == 1)
        #expect(sections.facts(of: .folded).count == 1)
        #expect(sections.facts(of: .calendar).count == 1)
        #expect(sections.facts(of: .memories).count == 1)
        #expect(sections.facts(of: .stage).count == 2)
        #expect(
            sections.summary == "2 learned · 1 state · 1 folded · 1 calendar · 1 memories · 2 stage"
        )
        #expect(FactPageSections.name(of: try EntityID(validating: "character:beaky")) == "Beaky")
    }
}

/// #229, Ship 2: April's checkboxes on a night's filing start from the world's review, and
/// after applying each row says what happened to it.
@Suite("Applying a night's filing")
struct FilingChecksTests {
    private func review() throws -> FilingReview {
        let april = try EntityID(validating: "person:april")
        let rules = try Fact(
            subjectID: april, predicate: "person.flight_rules", value: .string("flies VFR"),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_790_000_000), derivedFrom: [],
            producer: FactProducer(kind: "reducer", id: "given-facts", version: "1"))
        let proposal = LibrarianProposal(
            rewrites: [
                .init(
                    subject: april, predicate: "flight.rules", value: "Flies VFR.",
                    replaces: [rules.factID], reason: "beside the other flight facts")
            ],
            same: [
                .init(
                    ids: [
                        try EntityID(validating: "person:amber"),
                        try EntityID(validating: "thing:cleaner"),
                    ], keep: try EntityID(validating: "person:amber"), sure: false,
                    reason: "a role alone")
            ],
            kinds: [.init(predicate: "visitor.expected", meaning: "x")])
        let filing = try WorldEventEnvelope(
            type: WorldEventType(validating: "memory.filed"),
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            source: EventSource(id: SourceID(validating: "mind:beaky"), kind: "mind"),
            subjectIDs: [try EntityID(validating: "character:beaky")],
            epistemic: EpistemicState(type: .remembered, confidence: 1), payload: [:])
        return FilingReview(
            filing: filing, proposal: proposal,
            items: [
                .init(key: .init(.rewrites, 0), status: .ready, checked: true),
                .init(
                    key: .init(.same, 0), status: .ready, reason: "not sure: April's to decide",
                    checked: false, moves: [FactID.generated()]),
                .init(
                    key: .init(.kinds, 0), status: .guarded,
                    reason: "visitor.expected has its own rules",
                    checked: false),
            ],
            facts: [rules])
    }

    @Test("Rows say what each item would do, with what a rewrite replaces")
    func rowsDescribeTheItems() throws {
        let rows = NightlyReports.rows(of: try review())
        #expect(rows.map(\.key.list) == [.rewrites, .same, .kinds])
        #expect(rows[0].title == "person:april · flight.rules")
        #expect(rows[0].replaced == ["person.flight_rules = flies VFR"])
        #expect(rows[0].detail == "replaces 1 fact · beside the other flight facts")
        #expect(rows[1].body == "keep person:amber (not sure)")
        #expect(rows[1].detail == "moves 1 fact · a role alone")
    }

    @Test("Checks start from the review; only a ready item can be checked")
    func checksStartFromTheReview() throws {
        var checks = NightlyReports.FilingChecks(review: try review())
        #expect(checks.checked == [.init(.rewrites, 0)])
        checks.set(.init(.kinds, 0), checked: true)
        #expect(!checks.isChecked(.init(.kinds, 0)))
        checks.set(.init(.same, 0), checked: true)
        #expect(checks.selection == FilingSelection(rewrites: [0], same: [0]))
    }

    @Test("After applying, a row shows its outcome, not what was asked")
    func badgesShowOutcomes() throws {
        let review = try review()
        var checks = NightlyReports.FilingChecks(review: review)
        #expect(NightlyReports.badge(review.items[1], outcome: nil) == "April's call")
        #expect(NightlyReports.badge(review.items[2], outcome: nil) == "guarded")
        checks.record(
            FilingApplyResult(
                outcomes: [
                    .init(
                        key: .init(.rewrites, 0), applied: false, reason: "changed since the night")
                ], event: nil))
        let outcome = checks.outcomes[.init(.rewrites, 0)]
        #expect(NightlyReports.badge(review.items[0], outcome: outcome) == "skipped")
    }
}

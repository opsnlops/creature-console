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

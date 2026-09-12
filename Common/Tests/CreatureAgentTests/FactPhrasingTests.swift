import Foundation
import Testing
import WorldCore

@testable import creature_agent

@Suite("What you know")
struct FactPhrasingTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let april = try! EntityID(validating: "person:april")
    private let home = try! EntityID(validating: "region:home")

    @Test(
        "Facts become plain sentences, with assumptions marked and the character's own place skipped"
    )
    func factsBecomeSentences() throws {
        let facts = [
            try fact(mango, "presence.region", .string("region:home"), .observed, 1),
            try fact(beaky, "presence.region", .string("region:home"), .observed, 1),
            try fact(april, "presence.state", .string("home"), .assumed, 0.9),
            try fact(april, "presence.physically_audible", .bool(true), .assumed, 0.9),
            try fact(
                home, "scene.last",
                .object([
                    "lines": .array([
                        .object([
                            "character_id": .string("character:mango"),
                            "text": .string("It is always heat sinks."),
                        ])
                    ])
                ]), .observed, 1, validFrom: now.addingTimeInterval(-300)),
            try fact(home, "weather.mood", .string("gloomy"), .observed, 1),
        ]

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now)

        #expect(
            lines == [
                "Mango is here in the room with you.",
                "April is home (you assume; nobody has checked).",
                "5 minutes ago, in this room: Mango said \"It is always heat sinks.\".",
            ])
    }

    @Test("A person the world can only describe is described, and the blank is named")
    func thinPeopleAreMarked() throws {
        let polly = try EntityID(validating: "person:polly")
        let facts = [
            try fact(polly, WorldFacts.personDescription, .string("April's sister"), .reported, 1),
            try fact(april, WorldFacts.personDescription, .string("a wizard"), .reported, 1),
            try fact(april, WorldFacts.personState, .string("home"), .assumed, 0.9),
        ]

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now)

        #expect(
            lines == [
                "Polly is April's sister.",
                "April is a wizard.",
                "April is home (you assume; nobody has checked).",
                "That is all you know about Polly; do not make up more.",
            ])
    }

    @Test("A character the world knows the pronouns of is named with them")
    func pronounsRideWithTheName() throws {
        let facts = [
            try fact(mango, WorldFacts.characterRegion, .string("region:home"), .observed, 1),
            try fact(mango, WorldFacts.characterPronouns, .string("he/him"), .observed, 1),
            try fact(april, WorldFacts.personState, .string("home"), .assumed, 0.9),
        ]

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now)

        #expect(
            lines == [
                "Mango (he/him) is here in the room with you.",
                "April is home (you assume; nobody has checked).",
            ])
        #expect(FactPhrasing.pronouns(in: facts) == [mango: "he/him"])
    }

    @Test("The local time is spelled out in the house's zone, never the host's")
    func timeIsSpelledOutLocally() {
        // 2026-09-12 06:58:00 UTC is 11:58 PM on Friday, September 11 on Whidbey Island.
        let late = Date(timeIntervalSince1970: 1_789_196_280)
        #expect(
            FactPhrasing.timeSentence(late, in: TimeZone(identifier: "America/Los_Angeles")!)
                == "It is 11:58 PM on Friday, September 11.")
        #expect(
            FactPhrasing.timeSentence(late, in: TimeZone(identifier: "UTC")!)
                == "It is 6:58 AM on Saturday, September 12.")
    }

    @Test("The knowledge block always carries the time, and facts when there are any")
    func knowledgeBlockAlwaysHasTheTime() throws {
        let mind = CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: .text("You are Beaky."), characterID: beaky, personID: april,
                maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
                modelName: "test"),
            respond: { _ in "" }, logger: .init(label: "fact-phrasing-tests"))

        let timeOnly = mind.knowledgeBlock([], now: now)
        #expect(timeOnly.contains("What you know right now"))
        #expect(timeOnly.contains("- It is "))
        #expect(!timeOnly.contains("room"))
        let block = mind.knowledgeBlock(
            [try fact(mango, "presence.region", .string("region:home"), .observed, 1)], now: now)
        #expect(block.contains("- It is "))
        #expect(block.contains("- Mango is here in the room with you."))
    }

    private func fact(
        _ subject: EntityID, _ predicate: String, _ value: WorldJSONValue,
        _ type: EpistemicType, _ confidence: Double, validFrom: Date? = nil
    ) throws -> Fact {
        try Fact(
            subjectID: subject, predicate: predicate, value: value,
            epistemic: EpistemicState(type: type, confidence: confidence),
            validFrom: validFrom ?? now, derivedFrom: [],
            producer: FactProducer(kind: "test", id: "test", version: "1"))
    }
}

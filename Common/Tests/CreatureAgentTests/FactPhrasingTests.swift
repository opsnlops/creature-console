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

    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    @Test("Every fact takes one shape: who or where, what is known, since when, how it is known")
    func factsHaveOneShape() throws {
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

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now, in: pacific)

        // Beaky's own whereabouts and April's audibility are not for saying; everything else
        // is, including a predicate the agent has never heard of.
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("Mango · presence.region = This room · since "))
        #expect(lines[0].hasSuffix(" (just now) · observed"))
        #expect(lines[1].hasSuffix(" · assumed (nobody has checked) (90% sure)"))
        #expect(lines[1].hasPrefix("April · presence.state = home · since "))
        #expect(
            lines[2].hasPrefix(
                "This room · scene.last = Mango: \"It is always heat sinks.\" · since "))
        #expect(lines[2].contains("(5 minutes ago)"))
        #expect(lines[3].hasPrefix("This room · weather.mood = gloomy"))
    }

    @Test("Values render as themselves; entity IDs as names; expiries as until")
    func valuesRenderPlainly() throws {
        #expect(FactPhrasing.rendered(.string("unlocked")) == "unlocked")
        #expect(FactPhrasing.rendered(.string("April's sister")) == "\"April's sister\"")
        #expect(FactPhrasing.rendered(.string("place:front-door")) == "The front door")
        #expect(FactPhrasing.rendered(.number(67.14)) == "67.1")
        #expect(FactPhrasing.rendered(.number(2245)) == "2245")
        #expect(FactPhrasing.rendered(.bool(true)) == "yes")
        #expect(FactPhrasing.rendered(.null) == "none")
        #expect(
            FactPhrasing.rendered(.array([.string("Normal Evening"), .string("Movie Time")]))
                == "[\"Normal Evening\", \"Movie Time\"]")
        #expect(FactPhrasing.rendered(.object(["a": .number(1), "b": .string("x")])) == "a=1, b=x")
        let jesse = try EntityID(validating: "person:jesse")
        let expected = try Fact(
            subjectID: jesse, predicate: WorldFacts.visitorExpected,
            value: .string("this afternoon, to finish the deck"),
            epistemic: EpistemicState(type: .reported, confidence: 1),
            validFrom: now, validTo: now.addingTimeInterval(6 * 3_600), derivedFrom: [],
            producer: FactProducer(kind: "test", id: "test", version: "1"))
        let line = try #require(
            FactPhrasing.lines(for: [expected], character: beaky, now: now, in: pacific).first)
        #expect(
            line.hasPrefix(
                "Jesse · visitor.expected = \"this afternoon, to finish the deck\" · since "))
        #expect(line.contains(", until "))
        #expect(line.hasSuffix(" · reported"))
    }

    @Test("What just happened is told in order, with the clock and the age, in the world's words")
    func happeningsAreAStory() throws {
        let frontDoor = try EntityID(validating: "place:front-door")
        let carport = try EntityID(validating: "place:carport")
        let story = [
            Happening(
                occurredAt: now.addingTimeInterval(-300), type: HouseEvents.doorUnlocked,
                subjectID: frontDoor, summary: "The front door was just unlocked."),
            Happening(
                occurredAt: now.addingTimeInterval(-20), type: HouseEvents.personSeen,
                subjectID: carport),
        ]
        let lines = FactPhrasing.happeningLines(
            story, now: now, in: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" (5 minutes ago): The front door was just unlocked."))
        #expect(lines[1].hasSuffix(" (just now): camera.person_seen at the carport"))
        #expect(lines[0].contains(" PM ") || lines[0].contains(" AM "))
    }

    @Test("An expected visitor is a sentence, and the world says whether April is home")
    func expectedVisitorAndHome() throws {
        let jesse = try EntityID(validating: "person:jesse")
        let april = try EntityID(validating: "person:april")
        let facts = [
            try fact(
                jesse, WorldFacts.personDescription, .string("April's contractor"), .reported, 1),
            try fact(
                jesse, WorldFacts.visitorExpected, .string("this afternoon, to look at the deck"),
                .reported, 1),
            try fact(april, WorldFacts.personState, .string("away"), .observed, 1),
        ]
        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now, in: pacific)
        #expect(
            lines.contains { $0.hasPrefix("Jesse · person.description = \"April's contractor\"") })
        #expect(
            lines.contains {
                $0.hasPrefix("Jesse · visitor.expected = \"this afternoon, to look at the deck\"")
            })
        #expect(FactPhrasing.isHome(april, in: facts) == false)
        #expect(FactPhrasing.isHome(jesse, in: facts) == nil)
    }

    @Test("The house's facts take the same shape, and the lights are just a list")
    func houseFactsHaveTheShape() throws {
        let frontDoor = try EntityID(validating: "place:front-door")
        let outside = try EntityID(validating: "place:outside")
        let house = try EntityID(validating: "house:aprils-nest")
        let facts = [
            try fact(
                frontDoor, WorldFacts.doorLock, .string("unlocked"), .observed, 1,
                validFrom: now.addingTimeInterval(-20)),
            try fact(outside, "environment.temperature_f", .number(68.3), .observed, 1),
            try fact(frontDoor, "seen.person", .bool(true), .observed, 1),
            try fact(
                house, WorldFacts.houseScenes,
                .array([.string("Normal Evening"), .string("Movie Time")]), .observed, 1),
        ]

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now, in: pacific)

        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("The front door · door.lock = unlocked · since "))
        #expect(lines[1].hasPrefix("Outside · environment.temperature_f = 68.3 · since "))
        #expect(lines[2].hasPrefix("The front door · seen.person = yes · since "))
        #expect(
            lines[3].hasPrefix(
                "The house · house.scenes = [\"Normal Evening\", \"Movie Time\"] · since "))
        #expect(FactPhrasing.placeName(of: frontDoor) == "The front door")
        #expect(FactPhrasing.placeName(of: outside) == "Outside")
    }

    @Test("A watching camera that has seen nothing is a sentence, not a shrug")
    func quietCamerasAreAFact() throws {
        let frontDoor = try EntityID(validating: "place:front-door")
        let driveway = try EntityID(validating: "place:driveway")
        let carport = try EntityID(validating: "place:carport")
        let watching = [
            try fact(frontDoor, WorldFacts.cameraWatching, .bool(true), .observed, 1),
            try fact(driveway, WorldFacts.cameraWatching, .bool(true), .observed, 1),
            try fact(carport, WorldFacts.cameraWatching, .bool(true), .observed, 1),
        ]

        #expect(
            FactPhrasing.lines(for: watching, character: beaky, now: now, in: pacific) == [
                "The cameras at the front door, the driveway and the carport have seen nobody and nothing in the last ten minutes."
            ])
        // One that has seen something drops out of the quiet list.
        let busy = watching + [try fact(driveway, "seen.vehicle", .bool(true), .observed, 1)]
        let busyLines = FactPhrasing.lines(for: busy, character: beaky, now: now, in: pacific)
        #expect(busyLines.count == 2)
        #expect(busyLines[0].hasPrefix("The driveway · seen.vehicle = yes · since "))
        #expect(
            busyLines[1]
                == "The cameras at the front door and the carport have seen nobody and nothing in the last ten minutes."
        )
        #expect(
            FactPhrasing.lines(for: [watching[0]], character: beaky, now: now, in: pacific) == [
                "The camera at the front door has seen nobody and nothing in the last ten minutes."
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

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now, in: pacific)

        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("Polly · person.description = \"April's sister\" · since "))
        #expect(lines[1].hasPrefix("April · person.description = \"a wizard\" · since "))
        #expect(lines[3] == "That is all you know about Polly; do not make up more.")
    }

    @Test("Pronouns are read from the facts and never said as a fact")
    func pronounsRideWithTheName() throws {
        let facts = [
            try fact(mango, WorldFacts.characterRegion, .string("region:home"), .observed, 1),
            try fact(mango, WorldFacts.characterPronouns, .string("he/him"), .observed, 1),
            try fact(april, WorldFacts.personState, .string("home"), .assumed, 0.9),
        ]

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now, in: pacific)

        // Pronouns ride with the name in the persona, not as a line of their own.
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Mango · presence.region = This room"))
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
        #expect(!timeOnly.contains("Your mind runs on"))
        var knowing = mind.configuration
        knowing.modelLabel = "openai/gpt-6-astra"
        let told = CharacterMind(
            configuration: knowing, respond: { _ in "" },
            logger: .init(label: "fact-phrasing-tests"))
        #expect(
            told.knowledgeBlock([], now: now).contains(
                "- Your mind runs on the openai/gpt-6-astra model."))
        let block = mind.knowledgeBlock(
            [try fact(mango, "presence.region", .string("region:home"), .observed, 1)],
            meanings: ["presence.region": "which room a bird's mind is logged into"], now: now)
        #expect(block.contains("- It is "))
        #expect(block.contains("- Mango · presence.region = This room · since "))
        #expect(block.contains("What those kinds of fact mean:\n- presence.region: which room"))
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

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

    @Test("The house speaks plainly: doors, motion, the temperature, and the lights")
    func houseFactsAreSentences() throws {
        let frontDoor = try EntityID(validating: "place:front-door")
        let entryway = try EntityID(validating: "place:entryway")
        let outside = try EntityID(validating: "place:outside")
        let house = try EntityID(validating: "house:aprils-nest")
        let facts = [
            try fact(
                frontDoor, WorldFacts.doorLock, .string("unlocked"), .observed, 1,
                validFrom: now.addingTimeInterval(-20)),
            try fact(
                entryway, WorldFacts.motionActive, .bool(true), .observed, 1,
                validFrom: now.addingTimeInterval(-90)),
            try fact(outside, "environment.temperature_f", .number(68.3), .observed, 1),
            try fact(frontDoor, "seen.person", .bool(true), .observed, 1),
            try fact(
                try EntityID(validating: "place:driveway"), "seen.vehicle", .bool(true),
                .observed, 1, validFrom: now.addingTimeInterval(-200)),
            try fact(
                house, WorldFacts.houseScenes,
                .array([.string("Normal Evening"), .string("Movie Time")]), .observed, 1),
            try fact(
                house, WorldFacts.houseSceneRequested, .string("Normal Evening"), .observed, 1),
            try fact(
                house, WorldFacts.houseScene, .string("Movie Time"), .observed, 1,
                validFrom: now.addingTimeInterval(-3_600 * 2)),
        ]

        let lines = FactPhrasing.lines(for: facts, character: beaky, now: now)

        #expect(
            lines == [
                "The front door was unlocked just now.",
                "Someone moved in the entryway 1 minute ago.",
                "It is about 68 degrees outside.",
                "A person was seen at the front door just now.",
                "A vehicle was seen at the driveway 3 minutes ago.",
                "The house can set the lights to these scenes: Normal Evening, Movie Time. You cannot set them yourself: the house acts when April names one, and you will be told here when it does. Never say the lights are changing unless you are told so below; if April asks and you were not told, say the house did not catch it and ask her to name the scene.",
                "April just asked for the lights to be set to Normal Evening, and the house is doing it right now.",
                "The lights are set to Movie Time (since 2 hours ago).",
            ])
        #expect(FactPhrasing.placeName(of: frontDoor) == "The front door")
        #expect(FactPhrasing.placeName(of: outside) == "Outside")
    }

    @Test("Weather and power have words, with the judgement built in")
    func weatherAndPowerAreSentences() throws {
        let outside = try EntityID(validating: "place:outside")
        let house = try EntityID(validating: "house:aprils-nest")
        func line(_ subject: EntityID, _ predicate: String, _ value: Double) throws -> String? {
            FactPhrasing.sentence(
                for: try fact(subject, "environment." + predicate, .number(value), .observed, 1),
                character: beaky, now: now)
        }
        #expect(try line(outside, "wind_mph", 0) == "The air is still outside.")
        #expect(
            try line(outside, "wind_mph", 8)
                == "There is a light wind outside, about 8 miles per hour.")
        #expect(
            try line(outside, "wind_mph", 18.4) == "It is windy outside: about 18 miles per hour.")
        #expect(
            try line(outside, "wind_mph", 34)
                == "It is very windy outside: about 34 miles per hour. Things may blow around.")
        #expect(try line(outside, "rain_today_in", 0) == "It has not rained today.")
        #expect(try line(outside, "rain_today_in", 0.34) == "It has rained 0.3 inches today.")
        #expect(try line(outside, "rain_today_in", 1.0) == "It has rained 1.0 inch today.")
        #expect(
            try line(outside, "pressure_hpa", 996.3)
                == "The barometer reads about 996 hectopascals.")
        #expect(try line(outside, "humidity_percent", 63) == "The humidity outside is 63 percent.")
        #expect(
            try line(outside, "pm25_ugm3", 5.3)
                == "The air outside is clean (fine particles about 5 micrograms per cubic meter).")
        #expect(
            try line(outside, "pm25_ugm3", 60)
                == "The air outside is bad; everyone should stay inside (fine particles about 60 micrograms per cubic meter)."
        )
        #expect(
            try line(house, "power_w", 2244.9)
                == "The house is drawing about 2.2 kilowatts right now.")
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
            FactPhrasing.lines(for: watching, character: beaky, now: now) == [
                "The cameras at the front door, the driveway and the carport have seen nobody and nothing in the last ten minutes."
            ])
        // One that has seen something drops out of the quiet list.
        let busy = watching + [try fact(driveway, "seen.vehicle", .bool(true), .observed, 1)]
        #expect(
            FactPhrasing.lines(for: busy, character: beaky, now: now) == [
                "A vehicle was seen at the driveway just now.",
                "The cameras at the front door and the carport have seen nobody and nothing in the last ten minutes.",
            ])
        #expect(
            FactPhrasing.lines(for: [watching[0]], character: beaky, now: now) == [
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

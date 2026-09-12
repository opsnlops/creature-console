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

    @Test("The knowledge block is absent when the world knows nothing")
    func emptyKnowledgeIsSilent() throws {
        let mind = CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: "You are Beaky.", characterID: beaky, personID: april,
                maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
                modelName: "test"),
            respond: { _ in "" }, logger: .init(label: "fact-phrasing-tests"))

        #expect(mind.knowledgeBlock([], now: now).isEmpty)
        let block = mind.knowledgeBlock(
            [try fact(mango, "presence.region", .string("region:home"), .observed, 1)], now: now)
        #expect(block.contains("What you know right now"))
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

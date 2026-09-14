import Foundation
import Testing
import WorldCore

@testable import creature_agent

@Suite("What April tells her")
struct LearningTests {
    private let house = try! EntityID(validating: "house:aprils-nest")
    private var names: EntityNames {
        EntityNames(
            houseID: house,
            characters: [
                try! EntityID(validating: "character:beaky"),
                try! EntityID(validating: "character:kenny"),
            ])
    }

    @Test("Tags become facts; names become entities; bad tags are ignored; three at most")
    func tagsBecomeFacts() throws {
        let raw = """
            Tuesday it is.
            [learned: Jesse | visitor.expected | Tuesday afternoon, to finish the deck | tomorrow]
            [learned: the front door | sighting.identified | the postman | today]
            [learned: the house | house.note | the deck is getting boards | week]
            [learned: person:polly | person.description | April's sister | never]
            [learned: nonsense]
            [learned: Jesse | not a predicate | x | never]
            [learned: Jesse | person.description | x | someday]
            """
        let facts = LearnedFact.all(in: raw, names: names)
        #expect(facts.count == 3)
        #expect(facts[0].subjectID.rawValue == "person:jesse")
        #expect(facts[0].predicate == "visitor.expected")
        #expect(facts[0].value == "Tuesday afternoon, to finish the deck")
        #expect(facts[0].expiry == .tomorrow)
        #expect(facts[1].subjectID.rawValue == "place:front-door")
        #expect(facts[2].subjectID == house)
        #expect(names.entity(named: "Polly")?.rawValue == "person:polly")
        #expect(
            names.entity(named: "the back driveway")?.rawValue
                == "place:back-driveway")
        #expect(
            names.entity(named: "person:jesse")?.rawValue == "person:jesse")
        #expect(names.entity(named: "character:beaky")?.rawValue == "character:beaky")
        // A bird's name is the bird, never a person; a name nobody in the room has is a person.
        #expect(names.entity(named: "Kenny")?.rawValue == "character:kenny")
        #expect(names.entity(named: "kenny")?.rawValue == "character:kenny")
        #expect(names.entity(named: "Mango")?.rawValue == "person:mango")
        #expect(names.entity(named: "") == nil)
    }

    @Test("The tags never reach the room")
    func tagsAreStripped() {
        let raw =
            "Tuesday it is. [learned: Jesse | visitor.expected | Tuesday, deck | tomorrow] See you then."
        #expect(LearnedFact.stripped(raw) == "Tuesday it is.  See you then.")
        #expect(
            CharacterMind.validate(raw, spokenBy: "beaky") == "Tuesday it is. See you then.")
        #expect(
            CharacterMind.validate(
                "[learned: Jesse | visitor.expected | Tuesday | week]", spokenBy: "beaky") == nil)
    }

    @Test("Expiries are counted in the house's day")
    func expiries() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-09-13 20:00 PDT
        let now = Date(timeIntervalSince1970: 1_789_354_800)
        #expect(LearnedFact.Expiry.today.seconds(from: now, in: pacific) == 4 * 3_600.0)
        #expect(LearnedFact.Expiry.tomorrow.seconds(from: now, in: pacific) == 28 * 3_600.0)
        #expect(LearnedFact.Expiry.week.seconds(from: now, in: pacific) == 7 * 86_400.0)
        #expect(LearnedFact.Expiry.never.seconds(from: now, in: pacific) == nil)
    }
}

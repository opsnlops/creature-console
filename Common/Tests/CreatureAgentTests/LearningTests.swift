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
        // A named thing, when the mind says so; the house by any spelling of its kind.
        #expect(names.entity(named: "thing: Hopper")?.rawValue == "thing:hopper")
        #expect(names.entity(named: "Thing: the Prusa printer")?.rawValue == "thing:prusa-printer")
        #expect(names.entity(named: "house: April's nest") == house)
        #expect(names.entity(named: "robot: Kenny") == nil)
        #expect(names.entity(named: "") == nil)
    }

    @Test("Only a name that looks like a person's is a person; spells, things, and groups are not")
    func thingsAreNotPeople() {
        // What the birds really filed as people, 2026-09-13 to 09-22.
        #expect(names.entity(named: "new spell")?.rawValue == "thing:new-spell")
        #expect(names.entity(named: "spell: the TV spell")?.rawValue == "spell:tv-spell")
        #expect(names.entity(named: "Mac Studio")?.rawValue == "thing:mac-studio")
        #expect(names.entity(named: "Creature Server")?.rawValue == "thing:creature-server")
        #expect(
            names.entity(named: "Mukilteo Clinton Ferry")?.rawValue
                == "thing:mukilteo-clinton-ferry")
        #expect(names.entity(named: "car charger")?.rawValue == "thing:car-charger")
        #expect(names.entity(named: "Pi Picos")?.rawValue == "thing:pi-picos")
        #expect(names.entity(named: "church event")?.rawValue == "thing:church-event")
        #expect(names.entity(named: "April's bedroom")?.rawValue == "place:april-s-bedroom")
        #expect(names.entity(named: "Wednesday 8 AM labs")?.rawValue == "thing:wednesday-8-am-labs")
        // Groups are nobody.
        #expect(names.entity(named: "Kenny and Mango") == nil)
        #expect(names.entity(named: "all three birds") == nil)
        #expect(names.entity(named: "Beaky, Mango, and Kenny") == nil)
        // People still are.
        #expect(names.entity(named: "Tamara")?.rawValue == "person:tamara")
        #expect(names.entity(named: "Adlai Erickson")?.rawValue == "person:adlai-erickson")
        #expect(names.entity(named: "Susan")?.rawValue == "person:susan")
        // The record of a day from before spells still says `person:mac-studio`; the memory
        // model copies it back. It is a thing, whichever the record or the model says.
        var stale = names
        stale.add([
            try! EntityID(validating: "person:mac-studio"),
            try! EntityID(validating: "person:creature-server"),
        ])
        #expect(stale.entity(named: "person: Mac Studio")?.rawValue == "thing:mac-studio")
        #expect(stale.entity(named: "Creature Server")?.rawValue == "thing:creature-server")
        #expect(stale.knownEntity(named: "person:creature-server") == nil)
        stale.add([try! EntityID(validating: "thing:mac-studio")])
        #expect(stale.knownEntity(named: "person: Mac Studio")?.rawValue == "thing:mac-studio")
        // A real person the record already holds stays a person.
        stale.add([try! EntityID(validating: "person:tamara")])
        #expect(stale.entity(named: "person: Tamara")?.rawValue == "person:tamara")
        // The contract offers every kind.
        #expect(LearnedFact.contract.contains("spell: the TV spell"))
        #expect(LearnedFact.contract.contains("thing: Mac Studio"))
        #expect(WorldFacts.linkKinds.contains("spell"))
    }

    @Test("A name the world already holds is that entity, whatever kind the mind wrote")
    func knownEntitiesWin() throws {
        var known = names
        known.add([
            try EntityID(validating: "thing:information-bridge"),
            try EntityID(validating: "place:orchard"),
            try EntityID(validating: "order:amazon-123"),
        ])
        // Mango wrote "person: Information Bridge"; the world knows it as a thing.
        #expect(
            known.entity(named: "person: Information Bridge")?.rawValue
                == "thing:information-bridge")
        #expect(
            known.entity(named: "the Information Bridge")?.rawValue == "thing:information-bridge")
        #expect(known.entity(named: "Orchard")?.rawValue == "place:orchard")
        // Unknown names still get the mind's kind, or the guess.
        #expect(known.entity(named: "person: Tamara")?.rawValue == "person:tamara")
        #expect(known.entity(named: "Polly")?.rawValue == "person:polly")
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

    @Test("In a scene, the tags never reach the room either - even cut across two sentences")
    func tagsAreStrippedWhileStreaming() {
        var inTag = false
        // The whole tag in the last sentence, as Beaky's "excellent wizard maintenance" line had it.
        let last = CharacterMind.scenePiece(
            "That is excellent wizard maintenance. [learned: April medical.labs getting Dr. Montgomery labs now today]",
            first: false, characterName: "Beaky", speaker: nil, inTag: &inTag)
        #expect(last == "That is excellent wizard maintenance.")
        #expect(!inTag)
        // A tag the sentence splitter cut at the period inside its value.
        let head = CharacterMind.scenePiece(
            "Glad it went well. [learned: April | medical.labs | labs with Dr. Montgomery.",
            first: true, characterName: "Beaky", speaker: nil, inTag: &inTag)
        #expect(head == "Glad it went well.")
        #expect(inTag)
        let tail = CharacterMind.scenePiece(
            " | today] See you soon.", first: false, characterName: "Beaky", speaker: nil,
            inTag: &inTag)
        #expect(tail == "See you soon.")
        #expect(!inTag)
        // A piece that is nothing but the tag's tail is nothing to say.
        inTag = true
        #expect(
            CharacterMind.scenePiece(
                "now today]", first: false, characterName: "Beaky", speaker: nil, inTag: &inTag)
                == nil)
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

    @Test("A value of none ends a fact: a visitor April says has gone is no longer expected")
    func noneEndsAFact() {
        // 2026-09-23: "You can quit bugging me about Jesse, he's gone now."
        let facts = LearnedFact.all(
            in: "Sorry, April. [learned: Jesse | visitor.expected | none | today]", names: names)
        #expect(facts.count == 1)
        #expect(facts[0].subjectID.rawValue == "person:jesse")
        #expect(facts[0].ends)
        #expect(
            !LearnedFact(
                subjectID: facts[0].subjectID, predicate: "visitor.expected",
                value: "later today", expiry: .today
            ).ends)
        #expect(LearnedFact.contract.contains("visitor.expected | none"))
    }

}

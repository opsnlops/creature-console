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
            [learned: person: Jesse | visitor.expected | Tuesday afternoon, to finish the deck | tomorrow]
            [learned: place: the front door | sighting.identified | the postman | today]
            [learned: the house | house.note | the deck is getting boards | week]
            [learned: person:polly | person.description | April's sister | never]
            [learned: nonsense]
            [learned: person: Jesse | not a predicate | x | never]
            [learned: person: Jesse | person.description | x | someday]
            """
        let facts = LearnedFact.all(in: raw, names: names)
        #expect(facts.count == 3)
        #expect(facts[0].subjectID.rawValue == "person:jesse")
        #expect(facts[0].predicate == "visitor.expected")
        #expect(facts[0].value == "Tuesday afternoon, to finish the deck")
        #expect(facts[0].expiry == .tomorrow)
        #expect(facts[1].subjectID.rawValue == "place:front-door")
        #expect(facts[2].subjectID == house)
        #expect(names.entity(named: "place: the back driveway")?.rawValue == "place:back-driveway")
        #expect(names.entity(named: "person:jesse")?.rawValue == "person:jesse")
        #expect(names.entity(named: "character:beaky")?.rawValue == "character:beaky")
        // A bird's name is the bird, never a person; a bird nobody knows is no character.
        #expect(names.entity(named: "Kenny")?.rawValue == "character:kenny")
        #expect(names.entity(named: "kenny")?.rawValue == "character:kenny")
        #expect(names.entity(named: "character: Zed") == nil)
        // The kind the mind says; the house by any spelling of its kind.
        #expect(names.entity(named: "thing: Hopper")?.rawValue == "thing:hopper")
        #expect(names.entity(named: "Thing: the Prusa printer")?.rawValue == "thing:prusa-printer")
        #expect(names.entity(named: "place: Rocket Taco")?.rawValue == "place:rocket-taco")
        #expect(names.entity(named: "spell: the TV spell")?.rawValue == "spell:tv-spell")
        #expect(names.entity(named: "house: April's nest") == house)
        #expect(names.entity(named: "the house") == house)
        #expect(names.entity(named: "robot: Kenny") == nil)
        #expect(names.entity(named: "") == nil)
        // The contract asks for every kind.
        #expect(LearnedFact.contract.contains("place: Rocket Taco"))
        #expect(LearnedFact.contract.contains("spell: the TV spell"))
        #expect(LearnedFact.contract.contains("thing: Mac Studio"))
        #expect(WorldFacts.linkKinds.contains("spell"))
    }

    @Test("A bare new name is nobody's guess: no word list decides its kind (#239)")
    func bareNamesAreUnknown() {
        // What the word lists once decided - "Rocket Taco" was two capitalized words, so a
        // person - is now a judgement.
        #expect(names.naming("Rocket Taco") == .unknown(slug: "rocket-taco"))
        #expect(names.naming("Mac Studio") == .unknown(slug: "mac-studio"))
        #expect(names.naming("the front door") == .unknown(slug: "front-door"))
        #expect(names.naming("Tamara") == .unknown(slug: "tamara"))
        #expect(names.naming("Kenny and Mango") == .unknown(slug: "kenny-and-mango"))
        #expect(names.entity(named: "Rocket Taco") == nil)
        #expect(names.naming("five words is too many") == .none)
    }

    @Test("The judge names the kind from the line; nobody, a refusal, or no judge files nothing")
    func theJudgeNamesTheKind() async {
        let judge = ScriptedKindJudge(kinds: [
            "Rocket Taco": "place", "Tamara": "person", "Kenny and Mango": nil,
        ])
        #expect(
            await names.resolve("Rocket Taco", context: "lunch Saturday", judge: judge)?.rawValue
                == "place:rocket-taco")
        #expect(
            await names.resolve("Tamara", context: "", judge: judge)?.rawValue == "person:tamara")
        #expect(await names.resolve("Kenny and Mango", context: "", judge: judge) == nil)
        // A failed call, or none to ask: unfiled rather than guessed.
        #expect(await names.resolve("Hopper", context: "", judge: judge) == nil)
        #expect(await names.resolve("Rocket Taco", context: "", judge: nil) == nil)
        // A name the mind gave a kind, or the world holds, is never asked about.
        #expect(
            await names.resolve("thing: Hopper", context: "", judge: nil)?.rawValue
                == "thing:hopper")
        #expect(await judge.asked == ["Rocket Taco", "Tamara", "Kenny and Mango", "Hopper"])

        let raw = """
            Saturday then! [learned: Rocket Taco | plan.lunch | Saturday with April | week]
            [learned: Kenny and Mango | bird.mood | grumpy | today]
            [learned: person: Jesse | visitor.expected | Tuesday | tomorrow]
            """
        let (facts, unnamed) = await LearnedFact.all(in: raw, names: names, judge: judge)
        #expect(facts.map(\.subjectID.rawValue) == ["place:rocket-taco", "person:jesse"])
        #expect(unnamed == ["Kenny and Mango"])
        // The conversation around the tag goes with it, before the reply.
        _ = await LearnedFact.all(
            in: "Got it. [learned: Tamara | visitor.expected | after lunch | today]", names: names,
            judge: judge, conversation: "April: Tamara is coming by after lunch for the ladder")
        let talk = await judge.contexts.last ?? ""
        #expect(talk.contains("April: Tamara is coming by after lunch"))
        #expect(talk.hasSuffix("The reply: Got it."))
        // The judge saw the tag and the reply, never the tags as spoken text.
        let line = await judge.contexts.last { $0.hasPrefix("[learned: Rocket Taco") }
        #expect(line?.contains("Saturday then!") == true)
    }

    @Test("A name the world already holds is that entity, whatever kind the mind wrote")
    func knownEntitiesWin() throws {
        var known = names
        known.add([
            try EntityID(validating: "thing:information-bridge"),
            try EntityID(validating: "place:orchard"),
            try EntityID(validating: "order:amazon-123"),
            try EntityID(validating: "person:tamara"),
        ])
        // Mango wrote "person: Information Bridge"; the world knows it as a thing.
        #expect(
            known.entity(named: "person: Information Bridge")?.rawValue
                == "thing:information-bridge")
        #expect(
            known.entity(named: "the Information Bridge")?.rawValue == "thing:information-bridge")
        #expect(known.entity(named: "Orchard")?.rawValue == "place:orchard")
        #expect(known.entity(named: "Tamara")?.rawValue == "person:tamara")
        #expect(known.knownEntity(named: "person: Tamara")?.rawValue == "person:tamara")
        // A new name gets the mind's kind; a bare one is not known.
        #expect(known.entity(named: "person: Polly")?.rawValue == "person:polly")
        #expect(known.knownEntity(named: "person: Polly") == nil)
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
            in: "Sorry, April. [learned: person: Jesse | visitor.expected | none | today]",
            names: names)
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

    @Test("Someone already here is kept for the visit, not the day (#228)")
    func visitorHereNowIsKeptForTheVisit() throws {
        // 2026-10-14: the propane supplier, kept until midnight at 8:22 AM.
        let names = EntityNames(houseID: try EntityID(validating: "house:aprils-nest"))
        let facts = LearnedFact.all(
            in: LearnedFact.contract
                .components(separatedBy: "never the whole day: ").last ?? "",
            names: names)
        let kept = try #require(facts.first)
        #expect(kept.subjectID.rawValue == "thing:propane-supplier")
        #expect(kept.predicate == "visitor.expected")
        #expect(kept.expiry == .span(2 * 3_600))
        #expect(LearnedFact.contract.contains("does not end a visit"))
    }


    @Test("\"Ignore the cameras for the next hour\" keeps a quiet on the house, for an hour (#220)")
    func camerasQuietForAnHour() throws {
        // 2026-10-06, the yard guy: "Ignore the cameras for the next hour."
        let quiet = try #require(
            LearnedFact.all(
                in:
                    "I will, April. [learned: the house | house.cameras_quiet | the yard guy is working | 1h]",
                names: names
            ).first)
        #expect(quiet.subjectID == house)
        #expect(quiet.predicate == WorldFacts.camerasQuiet)
        #expect(quiet.expiry == .span(3_600))
        #expect(quiet.expiry.seconds(from: Date(), in: .current) == 3_600)
        #expect(quiet.expiry.word == "1h")
        // "You can talk about the cameras again" ends it.
        let over = try #require(
            LearnedFact.all(
                in: "[learned: the house | house.cameras_quiet | none | 1h]", names: names
            ).first)
        #expect(over.ends)
        #expect(LearnedFact.contract.contains("house.cameras_quiet"))
    }

    @Test("\"I'm at the dentist\" keeps her place as a link; a value named like a subject is one")
    func placesAreLinks() throws {
        var names = self.names
        names.add([try EntityID(validating: "place:hangar")])
        let learned = LearnedFact.all(
            in: """
                Say hi to the hygienist.
                [learned: person: April | presence.place | place: the dentist | 2h]
                [learned: person: April | presence.place | place: The Hangar | 2h]
                [learned: person: April | appointment.time | 10:30 AM | today]
                """, names: names)
        #expect(
            learned.map(\.value) == ["place:dentist", "place:hangar", "10:30 AM"])
        #expect(learned.first?.subjectID.rawValue == "person:april")
        #expect(learned.first?.expiry == .span(7_200))
        // A bare value is what was said, never who: "home" is not the house.
        #expect(names.link("home") == nil)
        #expect(names.link("the house") == nil)
        #expect(names.link("thing: a very long name for one thing") == nil)
        #expect(LearnedFact.contract.contains("presence.place"))
        #expect(LearnedFact.contract.contains("place: the dentist"))
    }

    @Test("Spans: minutes and hours, at most twelve hours, never zero")
    func spans() {
        #expect(LearnedFact.Expiry(word: "30m") == .span(1_800))
        #expect(LearnedFact.Expiry(word: "2H") == .span(7_200))
        #expect(LearnedFact.Expiry(word: "12h") == .span(43_200))
        #expect(LearnedFact.Expiry(word: "13h") == nil)
        #expect(LearnedFact.Expiry(word: "0h") == nil)
        #expect(LearnedFact.Expiry(word: "1d") == nil)
        #expect(LearnedFact.Expiry(word: "h") == nil)
        #expect(LearnedFact.Expiry(word: "today") == .today)
        #expect(LearnedFact.Expiry.span(1_800).word == "30m")
    }

    @Test("April is always person:april - never a source that shares her name (2026-09-24)")
    func aprilStaysAPerson() {
        // The day's record carried `wizard:april` - the source of April's own corrections -
        // and it took her slug: two nights of memories about her went to `wizard:april`.
        var record = names
        record.add([
            try! EntityID(validating: "person:april"),
            try! EntityID(validating: "wizard:april"),
            try! EntityID(validating: "mind:beaky"),
        ])
        #expect(record.entity(named: "April")?.rawValue == "person:april")
        #expect(record.knownEntity(named: "April")?.rawValue == "person:april")
        #expect(record.entity(named: "wizard: April") == nil)
    }

}

/// A judge that answers from a script and remembers what it was asked; a name it has no
/// line for fails, as a refused or timed-out call would.
private actor ScriptedKindJudge: EntityKindJudging {
    let kinds: [String: String?]
    private(set) var asked: [String] = []
    private(set) var contexts: [String] = []

    init(kinds: [String: String?]) { self.kinds = kinds }

    func kind(of name: String, in context: String) async throws -> String? {
        asked.append(name)
        contexts.append(context)
        guard let kind = kinds[name] else { throw DecisionsClient.Failure.noAnswer }
        return kind
    }
}

@Suite("The house tag (#240)")
struct HouseTagTests {
    @Test("The first tag's scene, trimmed; none without one")
    func readsTheScene() {
        #expect(HouseTag.scene(in: "[house: Movie Time] Popcorn!") == "Movie Time")
        #expect(HouseTag.scene(in: "[house:Goodnight]") == "Goodnight")
        #expect(HouseTag.scene(in: "[house: A] and [house: B]") == "A")
        #expect(HouseTag.scene(in: "No tag here.") == nil)
        #expect(HouseTag.scene(in: "[house: ]") == nil)
        // Never spoken.
        #expect(
            CharacterMind.validate("[house: Movie Time] Popcorn mode, April!", spokenBy: "beaky")
                == "Popcorn mode, April!")
    }

    @Test("The contract names the scenes only when the mind decides")
    func contract() {
        let scenes = ["Movie Time", "Goodnight"]
        #expect(HouseTag.contract(nil).isEmpty)
        #expect(HouseTag.contract(HouseAsks(askedBy: .words, scenes: scenes)).isEmpty)
        #expect(HouseTag.contract(HouseAsks(askedBy: .mind, scenes: [])).isEmpty)
        let contract = HouseTag.contract(HouseAsks(askedBy: .mind, scenes: scenes))
        #expect(contract.contains("- Movie Time\n- Goodnight\n"))
        #expect(contract.contains("[house: the scene's exact name"))
        // Each scene on its own line, with what it does when the world says.
        let described = HouseTag.contract(
            HouseAsks(
                askedBy: .mind, scenes: scenes,
                descriptions: ["Goodnight": "everything off for the night"]))
        #expect(described.contains("- Goodnight: everything off for the night"))
        #expect(described.contains("- Movie Time\n"))
        // April may say it her way.
        #expect(contract.contains("\"make the evening normal\" is Normal Evening"))
    }

    @Test("A reply asks once, as soon as the tag has arrived")
    func asksOnceAtTheTag() async {
        let asked = AskedScenes()
        let learning = CharacterMind.Learning(askHouse: { await asked.note($0) })
        await learning.note("[house: Movie")
        #expect(await asked.scenes.isEmpty)
        await learning.note(" Time] Popcorn")
        #expect(await asked.scenes == ["Movie Time"])
        await learning.note("[house: Goodnight] and more.")
        #expect(await asked.scenes == ["Movie Time"])
    }
}

private actor AskedScenes {
    private(set) var scenes: [String] = []
    func note(_ scene: String) { scenes.append(scene) }
}

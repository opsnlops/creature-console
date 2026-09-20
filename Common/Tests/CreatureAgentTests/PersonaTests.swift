import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_agent

@Suite("Personas: who each bird is")
struct PersonaTests {
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let kenny = try! EntityID(validating: "character:kenny")
    private let april = try! EntityID(validating: "person:april")

    private let mangoYAML = """
        name: Mango
        version: 2
        pronouns: he/him
        about: |
          A parrot who has lived with Beaky for years and is not impressed by much.
        voice: "Dry, deadpan, short sentences. No exclamation marks unless truly surprised."
        cares_about: ["Linux", "being right", "April's parts orders arriving"]
        avoids: ["birdseed talk", "pretending to be excited"]
        relationships:
          character:beaky: "Affectionate rivalry. Thinks Beaky exaggerates and says so."
          character:kenny: "Protective; Kenny is the youngest."
          person:april: "Fond, in a grumpy way. Calls her out when she orders more parts."
        running_jokes: ["It's always heat sinks."]
        never: ["speak for another bird", "use emoji", "describe actions"]
        """

    @Test("A persona file decodes with snake_case keys and sensible defaults")
    func decodesPersona() throws {
        let persona = try Persona.load(from: write(mangoYAML))
        #expect(persona.name == "Mango")
        #expect(persona.version == 2)
        #expect(persona.pronouns == "he/him")
        #expect(
            persona.about
                == "A parrot who has lived with Beaky for years and is not impressed by much.")
        #expect(persona.caresAbout == ["Linux", "being right", "April's parts orders arriving"])
        #expect(
            persona.relationships["character:kenny"]
                == Persona.Relationship(feeling: "Protective; Kenny is the youngest."))
        #expect(persona.never.count == 3)
        #expect(persona.versionTag == "mango/2")

        let minimal = try Persona.load(from: write("name: Caroll\nabout: A quiet parrot.\n"))
        #expect(minimal.version == 1)
        #expect(minimal.relationships.isEmpty)
        #expect(minimal.versionTag == "caroll/1")
    }

    @Test("A persona without a name or an about, or with a bad version, is refused")
    func refusesEmptyPersonas() throws {
        #expect(throws: DecodingError.self) { try Persona.load(from: write("about: Someone.\n")) }
        #expect(throws: DecodingError.self) {
            try Persona.load(from: write("name: X\nabout: ''\n"))
        }
        #expect(throws: DecodingError.self) {
            try Persona.load(from: write("name: X\nabout: Y\nversion: 0\n"))
        }
    }

    @Test("Rendering is sectioned, deterministic, and names only the ones who are here")
    func rendersOnlyThePresent() throws {
        let persona = try Persona.load(from: write(mangoYAML))

        let rendered = persona.rendered(present: [april, beaky])

        #expect(
            rendered == """
                You are Mango (he/him). A parrot who has lived with Beaky for years and is not impressed by much.

                How you talk: Dry, deadpan, short sentences. No exclamation marks unless truly surprised.

                You care about: Linux; being right; April's parts orders arriving.

                You steer away from: birdseed talk; pretending to be excited.

                The ones here, and how you feel about them:
                - April: Fond, in a grumpy way. Calls her out when she orders more parts.
                - Beaky: Affectionate rivalry. Thinks Beaky exaggerates and says so.

                Running jokes: It's always heat sinks.

                Never: speak for another bird; use emoji; describe actions.
                """)
        #expect(!rendered.contains("Kenny"))
        #expect(persona.rendered(present: [april, beaky]) == rendered)
        // With the world's pronoun facts, the ones here are named with them.
        #expect(
            persona.rendered(present: [beaky], pronouns: [beaky: "she/her"])
                .contains("- Beaky (she/her): Affectionate rivalry"))
    }

    @Test("A relationship may state the other's pronouns; the world's own fact outranks it")
    func relationshipPronounsAreAFallback() throws {
        let persona = try Persona.load(
            from: write(
                """
                name: Beaky
                about: The lead.
                relationships:
                  character:mango:
                    pronouns: he/him
                    feeling: "Computer geek."
                  character:kenny: "Not very smart; you are kind to him."
                """))

        #expect(persona.relationships["character:mango"]?.pronouns == "he/him")
        #expect(persona.relationships["character:kenny"]?.pronouns == nil)
        let believed = persona.rendered(present: [mango, kenny])
        #expect(believed.contains("- Mango (he/him): Computer geek."))
        #expect(believed.contains("- Kenny: Not very smart; you are kind to him."))
        let told = persona.rendered(present: [mango], pronouns: [mango: "they/them"])
        #expect(told.contains("- Mango (they/them): Computer geek."))
        // Nobody with a relationship present: the section is absent, never empty.
        #expect(!persona.rendered(present: []).contains("The ones here"))
    }

    @Test("The mind renders the persona against who the facts and the scene say is present")
    func mindUsesPersonaWithCompany() throws {
        let persona = try Persona.load(from: write(mangoYAML))
        let mind = CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: .structured(persona), characterID: mango, personID: april,
                maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
                modelName: "test"),
            respond: { _, _ in "" }, logger: Logger(label: "persona-tests"))
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-house"),
            speakerID: april, addresseeIDs: [mango], text: "Mango, what is in the box?",
            modality: .typed, source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"), occurredAt: now, confidence: 1)
        let percept = try PersonUtterancePercept(
            considerationID: .generated(), characterID: mango, utterance: utterance,
            priorConversationItems: [], sceneID: nil,
            worldFacts: [
                try presence(kenny, "region:home"), try presence(beaky, .null),
                try Fact(
                    subjectID: kenny, predicate: WorldFacts.characterPronouns,
                    value: .string("he/him"),
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    validFrom: now, derivedFrom: [],
                    producer: FactProducer(kind: "reducer", id: "test", version: "1")),
            ])

        let system = mind.makeTranscript(for: percept, now: now)[0].content

        // Everyone the persona knows, sorted, the same text every call - and who is here now
        // said apart: Kenny is logged in, Beaky logged out, April is speaking.
        #expect(system.contains("The ones you know, and how you feel about them:"))
        // The world's pronoun fact rides with "here now", not the stable persona text.
        #expect(system.contains("- Kenny: Protective; Kenny is the youngest."))
        #expect(system.contains("- April: Fond"))
        #expect(system.contains("- Beaky:"))
        #expect(system.contains("Here now: April, Kenny (he/him)."))
        #expect(!system.contains("Here now: April, Kenny (he/him), Beaky"))
        #expect(system.contains("Never: speak for another bird"))
        #expect(system.contains("What you know right now"))

        let offer = try SceneTurnOffer(
            sceneID: .generated(), characterID: mango, responseID: .generated(),
            deadline: now.addingTimeInterval(8),
            trigger: SceneTrigger(
                kind: .personUtterance, eventID: .generated(), speakerID: april,
                text: "What is in the box?"),
            participants: [beaky, mango], turns: [], worldFacts: [])
        let sceneSystem = mind.makeSceneTranscript(for: offer, now: now)[0].content
        #expect(sceneSystem.contains("- Beaky: Affectionate rivalry"))
        #expect(sceneSystem.contains("Here now: Beaky, Mango"))
        #expect(!sceneSystem.contains("Here now: Beaky, Mango, Kenny"))
    }

    @Test("A scene the house opened gets the familiar's contract, not the security guard's")
    func houseRemarkContract() throws {
        let persona = try Persona.load(from: write(mangoYAML))
        let mind = CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: .structured(persona), characterID: beaky, personID: april,
                maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
                modelName: "test"),
            respond: { _, _ in "" }, logger: Logger(label: "persona-tests"))
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let away = try Fact(
            subjectID: april, predicate: WorldFacts.personState, value: .string("away"),
            epistemic: EpistemicState(type: .observed, confidence: 1), validFrom: now,
            derivedFrom: [], producer: FactProducer(kind: "test", id: "test", version: "1"))
        var offer = try SceneTurnOffer(
            sceneID: .generated(), characterID: beaky, responseID: .generated(),
            deadline: now.addingTimeInterval(8),
            trigger: SceneTrigger(
                kind: .worldEvent, eventID: .generated(),
                text: "A person was just seen at the carport."),
            participants: [beaky, kenny], turns: [], worldFacts: [away],
            recentHappenings: [
                Happening(
                    occurredAt: now.addingTimeInterval(-30), type: HouseEvents.doorUnlocked,
                    subjectID: try EntityID(validating: "place:front-door"),
                    summary: "The front door was just unlocked.")
            ])
        let lead = mind.makeSceneTranscript(for: offer, now: now)
        let system = lead[0].content
        #expect(system.contains("The house just noticed something"))
        #expect(system.contains("What just happened around you"))
        #expect(system.contains("(just now): The front door was just unlocked."))
        #expect(system.contains("never reply with [silence]"))
        #expect(system.contains("April is not home"))
        #expect(system.contains("not a security system"))
        #expect(system.contains("A guess must sound like a guess"))
        #expect(system.contains("never remark on her spelling"))
        #expect(!system.contains("A scene is unfolding"))
        #expect(lead[1].content.hasPrefix("(A person was just seen at the carport.)\n"))

        // Kenny, second, may add one reaction or stay quiet.
        offer.characterID = kenny
        offer.turns = [
            SceneTurn(
                characterID: beaky, responseID: .generated(), text: "Ooh, a visitor!",
                offeredAt: now, answeredAt: now)
        ]
        offer.worldFacts = []
        let second = mind.makeSceneTranscript(for: offer, now: now)[0].content
        #expect(second.contains("Add one short reaction"))
        #expect(second.contains("do not tell her again"))
        #expect(second.contains("You do not know whether April is home"))
    }

    @Test(
        "The presence sensor wins: home six minutes is her at the door; home for hours is her inside"
    )
    func presenceSensorIsTheAuthority() throws {
        // "They need to trust the presence sensor more": the house said April was home six
        // minutes before the front door locked, and the birds still said they could not tell.
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let justHome = CharacterMind.houseRemarkContract(
            others: ["Mango"], aprilHome: true, aprilSince: 6 * 60, isLead: true)
        #expect(justHome.contains("April came home 6 minutes ago"))
        #expect(
            justHome.contains(
                "A car in the driveway, a person in the carport, at the door, or inside right now is April coming in"
            ))
        #expect(justHome.contains("never hedge that a camera cannot tell"))
        let homeAllDay = CharacterMind.houseRemarkContract(
            others: [], aprilHome: true, aprilSince: 5 * 3_600, isLead: true)
        #expect(homeAllDay.contains("April is home - the house's presence sensor says so"))
        #expect(
            homeAllDay.contains(
                "anywhere on the cameras, inside or out, is April unless a visitor is expected"))
        // "I'm the only one that lives here, it's me": the household rule is in both contracts,
        // so a scene (April's own question) never calls her a workshop visitor either.
        #expect(homeAllDay.contains("April lives alone."))
        #expect(CharacterMind.sceneContractCore.contains("April lives alone."))
        #expect(CharacterMind.household.contains("never say that a camera cannot tell who it is"))
        let away = CharacterMind.houseRemarkContract(others: [], aprilHome: false, isLead: true)
        #expect(away.contains("a person at the house is somebody else"))
        #expect(away.contains("A guess must sound like a guess only when it is one"))
        // Through the transcript, from the presence fact's own age.
        let april = try EntityID(validating: "person:april")
        let home = try Fact(
            subjectID: april, predicate: WorldFacts.personState, value: .string("home"),
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: now.addingTimeInterval(-6 * 60), derivedFrom: [],
            producer: FactProducer(kind: "reducer", id: "house", version: "1"))
        let mind = CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: .text("You are Beaky."), characterID: beaky, personID: april,
                maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
                modelName: "test"),
            respond: { _, _ in "" }, logger: Logger(label: "persona-tests"))
        let offer = try SceneTurnOffer(
            sceneID: .generated(), characterID: beaky, responseID: .generated(),
            deadline: now.addingTimeInterval(8),
            trigger: SceneTrigger(
                kind: .worldEvent, eventID: .generated(), text: "The front door was just locked."),
            participants: [beaky], turns: [], worldFacts: [home])
        #expect(
            mind.makeSceneTranscript(for: offer, now: now)[0].content.contains(
                "April came home 6 minutes ago"))
    }

    @Test("The house's question lets her stay quiet, and the reason is read, never spoken")
    func quietIsAnAnswer() throws {
        #expect(
            CharacterMind.quietReason(in: "[quiet: the same van as every afternoon]")
                == "the same van as every afternoon")
        #expect(
            CharacterMind.quietReason(in: "  [Quiet: April is already in there] ")
                == "April is already in there")
        #expect(CharacterMind.quietReason(in: "[quiet:]") == "no reason given")
        #expect(CharacterMind.quietReason(in: "Ooh, a visitor!") == nil)
        #expect(
            CharacterMind.quietReason(in: "[pass: April was talking to Beaky]")
                == "April was talking to Beaky")
        #expect(CharacterMind.declinesToSpeak("[pass: nothing new]"))
        #expect(
            CharacterMind.sceneContract(others: ["Mango"]).contains(
                "reply with exactly [pass: why]"))
        #expect(CharacterMind.sceneContract(others: []).contains("Expect to pass most turns"))
        #expect(CharacterMind.declinesToSpeak("[quiet: nothing new]"))
        #expect(CharacterMind.validate("[quiet: nothing new]", spokenBy: "beaky") == nil)
        let must = CharacterMind.houseRemarkContract(others: [], aprilHome: true, isLead: true)
        let may = CharacterMind.houseRemarkContract(
            others: [], aprilHome: true, isLead: true, mayDecline: true)
        #expect(must.contains("never reply with [silence]"))
        #expect(!must.contains("[quiet:"))
        #expect(may.contains("reply with exactly [quiet: why]"))
        #expect(may.contains("something in it for April or something odd"))
    }

    @Test("Stage directions are never spoken: asterisks, parentheses, and brackets go")
    func stageDirectionsAreStripped() {
        #expect(
            CharacterMind.validate("*giggles* \"I love you all too, you know!", spokenBy: "kenny")
                == "I love you all too, you know!")
        #expect(
            CharacterMind.validate("(chuckles) Well, Mango, you sure know how.", spokenBy: "kenny")
                == "Well, Mango, you sure know how.")
        #expect(
            CharacterMind.validate("Oh [flaps wings] that is the best news.", spokenBy: "beaky")
                == "Oh that is the best news.")
        // Only a direction, nothing said: a pass, not an empty line.
        #expect(CharacterMind.validate("*preens quietly*", spokenBy: "kenny") == nil)
        // Ordinary parentheses in speech survive when they are the whole sentence's sense.
        #expect(
            CharacterMind.validate("Two plus two is four.", spokenBy: "mango")
                == "Two plus two is four.")
    }

    @Test("In a scene, a line that opens by hailing April loses the hail; nothing else moves")
    func openingVocativeIsDropped() {
        #expect(
            CharacterMind.withoutOpeningVocative("April, pizza sounds delightful!", name: "April")
                == "Pizza sounds delightful!")
        #expect(
            CharacterMind.withoutOpeningVocative("april! Kenny's hungry!", name: "April")
                == "Kenny's hungry!")
        #expect(
            CharacterMind.withoutOpeningVocative("Oh, April, you missed it.", name: "April")
                == "Oh, April, you missed it.")
        #expect(
            CharacterMind.withoutOpeningVocative("Beaky, don't exaggerate.", name: "April")
                == "Beaky, don't exaggerate.")
        #expect(
            CharacterMind.withoutOpeningVocative("April is a purple rabbit.", name: "April")
                == "April is a purple rabbit.")
        // Only the hail: the line stays as it was rather than becoming nothing.
        #expect(CharacterMind.withoutOpeningVocative("April!", name: "April") == "April!")
    }

    @Test("The personas the package ships all decode and name themselves")
    func shippedPersonasDecode() throws {
        let personas = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/personas")
        let files = try FileManager.default.contentsOfDirectory(atPath: personas.path)
            .filter { $0.hasSuffix(".yaml") }.sorted()
        #expect(files == ["beaky.yaml", "kenny.yaml", "mango.yaml"])
        for file in files {
            let persona = try Persona.load(from: personas.appendingPathComponent(file))
            #expect(persona.name.lowercased() + ".yaml" == file)
            #expect(persona.pronouns != nil)
            #expect(!persona.never.isEmpty)
        }
    }

    private func presence(_ character: EntityID, _ region: WorldJSONValue) throws -> Fact {
        try Fact(
            subjectID: character, predicate: WorldFacts.characterRegion, value: region,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: Date(timeIntervalSince1970: 1_789_600_000), derivedFrom: [],
            producer: FactProducer(kind: "reducer", id: "test", version: "1"))
    }

    private func presence(_ character: EntityID, _ region: String) throws -> Fact {
        try presence(character, .string(region))
    }

    private func write(_ yaml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("persona-\(UUID().uuidString).yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

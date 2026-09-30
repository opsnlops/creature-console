import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("The address book, as facts")
struct ContactsTests {
    private let jesse = try! EntityID(validating: "person:jesse")

    private func card(_ identifier: String = "card-jesse") -> ContactCard {
        ContactCard(
            identifier: identifier, givenName: "Jesse", familyName: "Alvarez", nickname: "",
            organization: "Alvarez Carpentry", jobTitle: "Carpenter",
            phones: ["mobile": "(360) 555-0100"], emails: ["work": "jesse@example.com"],
            addresses: ["work": "12 Mill Rd, Freeland WA 98249"],
            birthday: DateComponents(month: 3, day: 4), relations: ["friend": "April White"])
    }

    @Test("The whole card becomes facts; April's own word on the relationship wins")
    func cardBecomesFacts() {
        let facts = ContactFacts.facts(from: card(), mapping: ContactMapping(entityID: jesse))
        let byPredicate = Dictionary(uniqueKeysWithValues: facts.map { ($0.predicate, $0.value) })
        #expect(byPredicate["contact.name"] == .string("Jesse Alvarez"))
        #expect(byPredicate["contact.phone"] == .object(["mobile": .string("(360) 555-0100")]))
        #expect(byPredicate["contact.email"] == .object(["work": .string("jesse@example.com")]))
        #expect(byPredicate["contact.organization"] == .string("Alvarez Carpentry"))
        #expect(byPredicate["contact.job_title"] == .string("Carpenter"))
        #expect(byPredicate["contact.birthday"] == .string("March 4"))
        #expect(byPredicate["person.relationship"] == .string("April's friend"))
        #expect(byPredicate["contact.nickname"] == nil)

        let told = ContactFacts.facts(
            from: card(), mapping: ContactMapping(entityID: jesse, relationship: "my contractor"))
        #expect(
            told.first { $0.predicate == "person.relationship" }?.value == .string("my contractor"))
        #expect(
            ContactFacts.birthdayText(DateComponents(year: 1971, month: 3, day: 4))
                == "March 4, 1971")
        // Numbers, addresses, and emails are the world's alone.
        #expect(ContactFacts.worldOnly == ["contact.phone", "contact.email", "contact.address"])
        #expect(Set(ContactFacts.meanings.keys).isSuperset(of: ContactFacts.worldOnly))
    }

    @Test("Only mapped cards are cast; a change re-casts; an unmapping takes it all back")
    func mappingDrivesCasting() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "contacts-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let casts = Casts()
        let book = Book(cards: [card(), card("card-polly")])
        // Every closure is injected: the real Contacts store would put up a privacy prompt
        // no one on a CI runner can answer, and the test host would wait forever.
        let source = ContactsSource(
            directory: directory, read: { await book.cards },
            write: { identifier, value in await book.link(identifier, to: value) },
            readHome: { ["12 mulberry ln"] }
        ) {
            await casts.note($0)
        }
        await source.poll()
        #expect(await casts.events.isEmpty)  // nothing mapped, nothing said
        #expect(await source.homeStreets == ["12 mulberry ln"])

        try await source.setMapping(ContactMapping(entityID: jesse), for: "card-jesse")
        // The word went onto the card, where Contacts on any device can see and change it.
        #expect(await book.cards.first?.link == "person:jesse")
        let first = await casts.events
        #expect(first.count == 8)
        #expect(first.allSatisfy { $0.subjectIDs == [jesse] })
        #expect(first.allSatisfy { $0.source.id.rawValue == "bridge:contacts" })
        #expect(first.allSatisfy { $0.payload["valid_for_seconds"] == nil })

        // The same book again: nothing to say.
        await source.poll()
        #expect(await casts.events.count == 8)

        // Jesse's number changes: one fact re-cast. (The card keeps its word.)
        var changed = card()
        changed.link = "person:jesse"
        changed.phones = ["mobile": "(360) 555-0199"]
        await book.replace(changed)
        await source.poll()
        let after = await casts.events
        #expect(after.count == 9)
        #expect(after.last?.payload["predicate"] == .string("contact.phone"))

        // Unmapped: every fact taken back, as nothing valid for a second.
        try await source.setMapping(nil, for: "card-jesse")
        let retractions = await casts.events.dropFirst(9)
        #expect(retractions.count == 8)
        #expect(retractions.allSatisfy { $0.payload["value"] == .null })
        #expect(retractions.allSatisfy { $0.payload["valid_for_seconds"] == .number(1) })
        #expect(await source.status.state == .on)
    }

    @Test("Pronouns ride on the Beaky link, after the relationship or on their own")
    func pronounsOnTheLink() {
        #expect(
            ContactMapping(cardValue: "person:jesse; general contractor; he/him")
                == ContactMapping(
                    entityID: jesse, relationship: "general contractor", pronouns: "he/him"))
        #expect(
            ContactMapping(cardValue: "person:jesse; They / Them")
                == ContactMapping(entityID: jesse, pronouns: "they/them"))
        #expect(
            ContactMapping(cardValue: "person:jesse; she/they; my neighbor")
                == ContactMapping(
                    entityID: jesse, relationship: "my neighbor", pronouns: "she/they"))
        // Anything a pronoun list cannot hold is said outright.
        #expect(
            ContactMapping(cardValue: "person:jesse; pronouns: any pronouns")
                == ContactMapping(entityID: jesse, pronouns: "any pronouns"))
        // Slashes alone do not make pronouns: "friend/neighbor" is what they are to April.
        #expect(
            ContactMapping(cardValue: "person:jesse; friend/neighbor")
                == ContactMapping(entityID: jesse, relationship: "friend/neighbor"))
        // And back onto the card, in order.
        #expect(
            ContactMapping(entityID: jesse, relationship: "general contractor", pronouns: "he/him")
                .cardValue == "person:jesse; general contractor; he/him")
        #expect(
            ContactMapping(entityID: jesse, pronouns: "they/them").cardValue
                == "person:jesse; they/them")

        // Cast as the world's own pronouns predicate, beside the rest of the card.
        let facts = ContactFacts.facts(
            from: card(), mapping: ContactMapping(entityID: jesse, pronouns: "he/him"))
        #expect(facts.first { $0.predicate == WorldFacts.pronouns }?.value == .string("he/him"))
        #expect(
            !ContactFacts.facts(from: card(), mapping: ContactMapping(entityID: jesse))
                .contains { $0.predicate == WorldFacts.pronouns })
    }

    @Test("Contacts' refusal of a protected card is told apart from any other failure")
    func protectedCardRefusal() {
        #expect(
            BridgeStore.isProtectedCardRefusal(NSError(domain: NSCocoaErrorDomain, code: 134_092)))
        #expect(
            !BridgeStore.isProtectedCardRefusal(NSError(domain: NSCocoaErrorDomain, code: 134_030)))
        #expect(
            !BridgeStore.isProtectedCardRefusal(NSError(domain: "CNErrorDomain", code: 134_092)))
    }

    @Test("The card's own word is the map; a map from before is carried onto the cards once")
    func cardCarriesTheWord() async throws {
        #expect(
            ContactMapping(cardValue: "person:jesse; general contractor")
                == ContactMapping(entityID: jesse, relationship: "general contractor"))
        #expect(ContactMapping(cardValue: "Person:Jesse") == ContactMapping(entityID: jesse))
        #expect(ContactMapping(cardValue: "https://example.com") == nil)
        #expect(
            ContactMapping(entityID: jesse, relationship: "general contractor").cardValue
                == "person:jesse; general contractor")

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "contacts-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldMap = [
            "card-polly": ContactMapping(entityID: try EntityID(validating: "person:polly"))
        ]
        try WorldJSON.makeEncoder().encode(oldMap).write(
            to: directory.appending(path: "contacts-map.json"))
        var jesseCard = card()
        jesseCard.link = "person:jesse; general contractor"
        let book = Book(cards: [jesseCard, card("card-polly")])
        let casts = Casts()
        let source = ContactsSource(
            directory: directory, read: { await book.cards },
            write: { identifier, value in await book.link(identifier, to: value) },
            readHome: { [] }
        ) {
            await casts.note($0)
        }
        await source.poll()
        let map = await source.map
        #expect(map["card-jesse"]?.relationship == "general contractor")
        #expect(map["card-polly"]?.entityID.rawValue == "person:polly")
        #expect(await book.cards.last?.link == "person:polly")
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appending(path: "contacts-map.json").path))
        #expect(
            await casts.events.contains { $0.payload["value"] == .string("general contractor") })

        // Edited in Contacts, by hand: the next read follows the card.
        await book.link("card-jesse", to: nil)
        await source.poll()
        #expect(await source.map["card-jesse"] == nil)
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

private actor Book {
    private(set) var cards: [ContactCard]
    init(cards: [ContactCard]) { self.cards = cards }
    func replace(_ card: ContactCard) {
        cards = cards.map { $0.identifier == card.identifier ? card : $0 }
    }
    func link(_ identifier: String, to value: String?) {
        cards = cards.map {
            var card = $0
            if card.identifier == identifier { card.link = value }
            return card
        }
    }
}

import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("The texts, as facts")
struct MessagesTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    private let jesse = try! EntityID(validating: "person:jesse")
    private let house = try! EntityID(validating: "house:aprils-nest")
    // Tuesday 2026-09-15 13:40 PDT
    private let afternoon = Date(timeIntervalSince1970: 1_789_504_800)

    private var resolver: PersonResolver {
        PersonResolver(
            cards: [
                ContactCard(
                    identifier: "card-jesse", givenName: "Jesse", familyName: "Alvarez",
                    nickname: "", organization: "", jobTitle: "",
                    phones: ["mobile": "(360) 555-0100"], emails: ["work": "jesse@example.com"],
                    addresses: [:], birthday: nil, relations: [:])
            ],
            map: ["card-jesse": ContactMapping(entityID: jesse)])
    }

    private func text(
        _ row: Int64, from handle: String = "+13605550100", _ words: String, fromMe: Bool = false,
        group: Bool = false, minutesAgo: Double = 0, now: Date
    ) -> TextMessage {
        TextMessage(
            rowID: row, handle: handle, isFromMe: fromMe,
            date: now.addingTimeInterval(-minutesAgo * 60), text: words,
            chatIdentifier: group ? "chat123" : handle, isGroupChat: group)
    }

    @Test("A phone number on a text finds the card's person, however it is written")
    func handlesFindPeople() {
        #expect(resolver.person(handle: "+13605550100") == jesse)
        #expect(resolver.person(handle: "360-555-0100") == jesse)
        #expect(resolver.person(handle: "jesse@example.com") == jesse)
        #expect(resolver.person(handle: "+13605550199") == nil)
        #expect(PersonResolver.phoneKey("+1 (360) 555-0100") == "3605550100")
    }

    @Test("The words come out of an attributedBody; a date is nanoseconds since 2001")
    func decodesMessagesRows() {
        var body = Data([
            0x04, 0x0B, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D, 0x74, 0x79, 0x70, 0x65, 0x64,
        ])
        body += Data("NSString".utf8)
        body += Data([0x01, 0x94, 0x84, 0x01, 0x2B, 0x09])
        body += Data("on my way".utf8)
        body += Data([0x86, 0x84, 0x02, 0x69, 0x49])
        #expect(MessagesIntake.text(fromAttributedBody: body) == "on my way")
        var long = Data("NSString".utf8) + Data([0x2B, 0x81, 0x2C, 0x01])
        long += Data(String(repeating: "a", count: 300).utf8)
        #expect(MessagesIntake.text(fromAttributedBody: long).count == 300)
        #expect(MessagesIntake.text(fromAttributedBody: Data("nothing here".utf8)) == "")
        let nanos: Int64 = 780_000_000 * 1_000_000_000
        #expect(
            MessagesIntake.date(from: nanos) == Date(timeIntervalSinceReferenceDate: 780_000_000))
        #expect(
            MessagesIntake.date(from: 780_000_000)
                == Date(timeIntervalSinceReferenceDate: 780_000_000))
    }

    @Test("A visit holds until three hours past the time named, else two hours; news a week")
    func readingsHaveALifetime() {
        let said = afternoon  // 1:40 PM
        let six = MessageFacts.until(.visit, when: "there by 6", said: said, zone: pacific)
        #expect(six == said.addingTimeInterval((4 * 60 + 20 + 180) * 60))  // 9:00 PM
        let sixThirty = MessageFacts.namedTime(in: "around 6:30pm", after: said, zone: pacific)!
        #expect(sixThirty == said.addingTimeInterval((4 * 60 + 50) * 60))
        #expect(MessageFacts.until(.visit, when: "", said: said, zone: pacific) == said + 2 * 3_600)
        #expect(MessageFacts.until(.news, when: "", said: said, zone: pacific) == said + 7 * 86_400)
        #expect(MessageFacts.namedTime(in: "tonight", after: said, zone: pacific) == nil)
    }

    @Test("A reading becomes the fact on the person, with when it was texted beside it")
    func readingsBecomeFacts() {
        let told = MessageTold(
            rowID: 7, person: jesse, kind: .visit, what: "on the way", when: "",
            said: afternoon, until: afternoon + 7_200)
        let wanted = MessageFacts.wanted(told, house: house, now: afternoon + 60, zone: pacific)
        #expect(wanted.entityID == jesse)
        #expect(wanted.facts["visitor.expected"] == .string("on the way (texted 1:40 PM)"))
        #expect(wanted.validUntil == afternoon + 7_200)
        let news = MessageTold(
            rowID: 8, person: jesse, kind: .news, what: "got the job", when: "",
            said: afternoon, until: afternoon + 86_400)
        #expect(
            MessageFacts.wanted(news, house: house, now: afternoon + 2 * 86_400, zone: pacific)
                .facts["person.news"] == .string("got the job (texted Tuesday at 1:40 PM)"))
    }

    @Test("Senders are matched by their digits; the built-in carriers give way to a saved list")
    @MainActor func sendersAreAllowedByNumber() {
        #expect(TextSender(handle: "1 (800) 463-3339", name: "FedEx").id == "8004633339")
        #expect(TextSender(handle: "+18004633339", name: "FedEx").id == "8004633339")
        #expect(TextSender(handle: "28777", name: "USPS").id == "28777")
        let defaults = UserDefaults(suiteName: "messages-tests-\(UUID().uuidString)")!
        let connection = BridgeConnection(defaults: defaults, keyStore: nil)
        // Nothing saved: the carriers, plus what the old free-text field held.
        #expect(connection.messagesSenders == TextSender.defaults)
        defaults.set("555-0100, 69877", forKey: BridgeConnection.Keys.messagesExtraHandles)
        #expect(
            connection.messagesSenders
                == TextSender.defaults + [TextSender(handle: "555-0100", name: "the carrier")])
        // Saved: the list is the whole truth, a removed carrier included.
        let kept = [TextSender(handle: "1-800-463-3339", name: "FedEx")]
        connection.setMessagesSenders(kept)
        #expect(connection.messagesSenders == kept)
        connection.setMessagesSenders([])
        #expect(connection.messagesSenders.isEmpty)
    }

    @Test("Only texts from people April knows are read; April's own, groups, and chat are not")
    func sourceReadsOnlyWhatMatters() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "messages-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = afternoon
        let casts = Casts()
        let looked = Looked()
        let messages = [
            text(1, "on my way!", now: now),
            text(2, "see you soon", fromMe: true, now: now),
            text(3, from: "+13605550199", "on my way!", now: now),  // a stranger
            text(4, "on my way!", group: true, now: now),
            text(5, "lol", now: now),
            text(6, from: "28777", "Your package was left at the front door", now: now),
            text(7, "can you grab milk", minutesAgo: 3 * 24 * 60, now: now),  // days old
            // FedEx Delivery Manager, as Messages writes the number: a built-in carrier.
            text(8, from: "+1 (800) 463-3339", "Your package was delivered", now: now),
        ]
        let resolver = resolver
        let source = MessagesSource(
            directory: directory, house: house, zone: pacific, readGroupChats: false,
            senders: TextSender.defaults, lookbackDays: 1,
            fetch: { after, since in messages.filter { $0.rowID > (after ?? 0) && $0.date > since }
            },
            distill: { message, sender, context in
                await looked.note(message.rowID)
                await looked.note(sender: sender, context: context)
                if message.text.hasPrefix("on my way") {
                    return MessageReading(
                        kind: .visit, what: "on the way", when: "", quote: "on my way")
                }
                if message.text.hasPrefix("Your package") {
                    return MessageReading(
                        kind: .delivery, what: "package left at the front door", when: "",
                        quote: "left at the front door")
                }
                return MessageReading(kind: .nothing, what: "", when: "", quote: "")
            },
            modelCheck: { nil },
            resolver: { resolver }
        ) { await casts.note($0) }
        await source.poll(now: now)
        #expect(await looked.rows == [1, 5, 6, 8])
        // The model sees the thread so far - April's own line included - and who is talking.
        #expect(await looked.senders == ["Jesse", "Jesse", "USPS", "FedEx"])
        #expect(await looked.contexts[1] == ["Jesse: on my way!", "April: see you soon"])
        let events = await casts.events
        #expect(events.count == 3)
        let jesseVisit = events.first { $0.subjectIDs.first == jesse }
        #expect(jesseVisit?.payload["predicate"] == .string("visitor.expected"))
        #expect(jesseVisit?.payload["value"] == .string("on the way (texted 1:40 PM)"))
        #expect(jesseVisit?.source.id.rawValue == "bridge:messages")
        let deliveries = events.filter { $0.subjectIDs.first == house }
        #expect(deliveries.count == 2)
        #expect(deliveries.allSatisfy { $0.payload["predicate"] == .string("delivery.arrived") })
        // The carrier's name is in the fact, so a bird can say who came.
        #expect(
            deliveries.contains {
                $0.payload["value"]
                    == .string("FedEx: package left at the front door (texted 1:40 PM)")
            })
        #expect(await source.told.count == 3)
        // The stranger is offered in the window - the number, how often, how lately - so
        // April can allow it; the group chat is not.
        let skipped = await source.skippedSenders
        #expect(skipped.map(\.handle) == ["+13605550199"])
        #expect(skipped.first?.count == 1)
        #expect(skipped.first?.lastAt == now)

        // Nothing new: nothing said again. Two hours on, the visit has run out and is let go
        // without a retraction - the world expired it.
        await source.poll(now: now + 60)
        #expect(await casts.events.count == 3)
        await source.poll(now: now + 3 * 3_600)
        #expect(await casts.events.count == 3)
        #expect(await source.told.count == 2)
        #expect(await source.status.state == .on)
    }

    @Test("A reading stands only when its quote is in the text; the model's inventions do not")
    func quotesGuardAgainstInvention() {
        let text = "Would it be better if I picked you up?"
        #expect(
            !MessageDistiller.isSupported(
                MessageReading(
                    kind: .request, what: "asked April to grab milk", when: "", quote: "grab milk"),
                by: text))
        #expect(
            MessageDistiller.isSupported(
                MessageReading(kind: .visit, what: "on the way", when: "", quote: "On my  way"),
                by: "on my way to your place"))
        #expect(
            !MessageDistiller.isSupported(
                MessageReading(kind: .news, what: "got the job", when: "", quote: ""), by: text))
        #expect(
            MessageDistiller.isSupported(
                MessageReading(kind: .nothing, what: "", when: "", quote: ""), by: text))
    }

    @Test("A fact is a few words, never the message")
    func factsAreShort() {
        let long =
            "They’re now saying we need an engineer to do a site inspection of the roof system that you already have there and sign off on it before we can turn in the permit now."
        let short = MessageDistiller.shortened(long)
        #expect(short.count <= MessageDistiller.maximumFactCharacters + 1)
        #expect(short.hasSuffix("…"))
        #expect(MessageDistiller.shortened("Six puppies!") == "Six puppies!")
    }

    @Test("Without the model there is no reading, and the row says so")
    func noModelNoReading() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "messages-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = MessagesSource(
            directory: directory, house: house, readGroupChats: false, senders: [],
            fetch: { _, _ in [] }, distill: { _, _, _ in nil },
            modelCheck: { "no Apple Intelligence" },
            resolver: { PersonResolver(cards: [], map: [:]) }
        ) { _ in }
        await source.poll()
        #expect(await source.status.state == .degraded("no Apple Intelligence"))
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

private actor Looked {
    private(set) var rows: [Int64] = []
    private(set) var senders: [String] = []
    private(set) var contexts: [[String]] = []
    func note(_ row: Int64) { rows.append(row) }
    func note(sender: String, context: [String]) {
        senders.append(sender)
        contexts.append(context)
    }
}

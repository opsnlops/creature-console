import Foundation
import Logging
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

/// A whisper stays between April and one bird (#261), through the repositories the World runs
/// on: April's word and the bird's answer are marked where they are kept, every bird is handed
/// only what it heard, and the migration marks what was kept before.
@Suite(
    "Whispers in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct WhisperMongoTests {
    // Now, not a fixed day: ingresses and percepts expire, and a month-old one can be swept away
    // by the TTL monitor mid-test. Whole seconds, as the store keeps them, so a stored item is
    // the same item.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private let april = try! EntityID(validating: "person:april")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")

    private struct Harness {
        let persistence: MongoWorldPersistence
        let ingress: PersonUtteranceIngressService
        let router: CharacterDeliveryRouter
        let conversationID: ConversationID
        let april: EntityID
        let now: Date

        func say(_ text: String, minute: Double) async throws -> UtteranceIngressResult {
            try await ingress.ingest(
                try PersonUtterance(
                    conversationID: conversationID, speakerID: april,
                    addresseeIDs: [try EntityID(validating: "character:beaky")], text: text,
                    modality: .typed, source: .communicatorComposition,
                    sourceID: SourceID(validating: "communicator:test"),
                    occurredAt: now.addingTimeInterval(minute * 60), confidence: 1),
                context: UtteranceIngressContext(boundary: .trustedLAN))
        }

        func answer(_ said: UtteranceIngressResult, _ text: String) async throws
            -> CharacterDeliveryResult
        {
            try await router.route(
                try CharacterUtteranceIntent(
                    conversationID: conversationID, characterID: said.percept.characterID,
                    recipientID: april, inResponseToUtteranceID: said.percept.utterance.utteranceID,
                    text: text, urgency: 0.3,
                    createdAt: said.percept.utterance.occurredAt.addingTimeInterval(1)))
        }

        func items() async throws -> [ConversationItem] {
            try await persistence.conversations.conversationItems(
                in: conversationID, after: nil, limit: 50)
        }
    }

    private func harness() async throws -> Harness {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "whisper-tests"))
        let conversationID = try ConversationID(
            validating: "conversation:whisper-\(UUID().uuidString.lowercased())")
        return Harness(
            persistence: persistence,
            ingress: PersonUtteranceIngressService(
                repository: persistence.conversations, sink: AcceptingSink(),
                addresseeResolver: FlockResolver(
                    rule: LeadAddresseeRule(lead: beaky), present: ["beaky": beaky, "mango": mango])
            ),
            router: try CharacterDeliveryRouter(
                presenceProvider: AtHome(april: april, now: now),
                repository: persistence.characterDeliveries,
                physicalSpeechSink: AcceptingSink(), communicatorSink: AcceptingSink(),
                clock: ManualWorldClock(now: now)),
            conversationID: conversationID, april: april, now: now)
    }

    @Test("A whisper and its answer are kept marked, and only its bird is handed them")
    func whisperIsKeptMarked() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }

        let whisper = try await h.say("@beaky just between us", minute: 0)
        let answer = try await h.answer(whisper, "Just between us, April.")
        let toMango = try await h.say("Mango, how are the new speakers?", minute: 1)
        let toBeaky = try await h.say("Beaky, and you?", minute: 2)

        #expect(whisper.percept.characterID == beaky)
        #expect(answer.conversationItem.aloneWith == beaky)
        #expect(try await h.items().map(\.aloneWith) == [beaky, beaky, nil, nil])
        #expect(toMango.percept.characterID == mango)
        #expect(toMango.percept.priorConversationItems.isEmpty)
        #expect(
            toBeaky.percept.priorConversationItems.map(\.text) == [
                "@beaky just between us", "Just between us, April.",
                "Mango, how are the new speakers?",
            ])
        // A retry finds the same marked item: nothing conflicts.
        let retried = try await h.ingress.ingest(
            whisper.percept.utterance, context: UtteranceIngressContext(boundary: .trustedLAN))
        #expect(retried.disposition == .duplicate)
        #expect(try await h.answer(whisper, "Just between us, April.").disposition == .accepted)
    }

    @Test("The migration marks the whispers kept before it, and their answers, in every copy")
    func migrationMarksWhatWasKept() async throws {
        let h = try await harness()
        defer { Task { await h.persistence.cluster.disconnect() } }
        let whisper = try await h.say("hey @beaky, just us?", minute: 0)
        let answer = try await h.answer(whisper, "Just us.")
        _ = try await h.say("Goodnight, flock", minute: 1)
        // As they were kept before 0.64.2: no mark anywhere.
        let database = h.persistence.database
        let unmark: Document = ["$unset": ["alone_with": ""] as Document]
        _ = try await database[MongoWorldCollection.conversationItems].updateMany(
            where: ["conversation_id": h.conversationID.rawValue], to: unmark)
        let unmarkCopy: Document = ["$unset": ["conversationItem.alone_with": ""] as Document]
        _ = try await database[MongoWorldCollection.utteranceIngresses].updateOne(
            where: ["_id": whisper.percept.utterance.utteranceID.rawValue], to: unmarkCopy)
        _ = try await database[MongoWorldCollection.characterDeliveries].updateOne(
            where: ["_id": answer.conversationItem.responseID!.rawValue], to: unmarkCopy)
        #expect(try await h.items().allSatisfy { $0.aloneWith == nil })

        let marked = try await MongoWorldMigrator(
            database: database, logger: Logger(label: "whisper-tests")
        ).markWhispers()

        #expect(marked >= 2)
        #expect(try await h.items().map(\.aloneWith) == [beaky, beaky, nil])
        // The copies match the items again: reading them back re-saves the item, which would
        // be refused if they differed.
        let ingress = try await h.persistence.conversations.ingress(
            for: whisper.percept.utterance.utteranceID)
        #expect(ingress?.conversationItem.aloneWith == beaky)
        let delivery = try await h.persistence.characterDeliveries.delivery(
            for: try #require(answer.conversationItem.responseID))
        #expect(delivery?.conversationItem.aloneWith == beaky)
        #expect(
            try await h.persistence.characterDeliveries.whisperedTo(
                utterance: whisper.percept.utterance.utteranceID) == beaky)
    }
}

/// A fact a bird keeps while answering a whisper is that bird's alone (#263), on every path a
/// fact takes to a mind, and the migration marks what was kept before.
@Suite(
    "What a bird learns in a whisper, in MongoDB",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct WhisperedFactsMongoTests {
    // Now, not a fixed day: percepts and ingresses expire, and a month-old one can be swept
    // away by the TTL monitor mid-test. Whole seconds, as the store keeps them.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")

    @Test("Kept in a whisper, a fact reaches its bird alone: page, story, day, and the past")
    func whisperedFactIsItsBirdsAlone() async throws {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI), logger: .init(label: "whispered-facts-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let clock = ManualWorldClock(now: now)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [GivenFactReducer()], clock: clock)
        let suffix = UUID().uuidString.lowercased()
        let april = try EntityID(validating: "person:april-\(suffix)")
        let conversationID = try ConversationID(validating: "conversation:whisper-\(suffix)")
        let percepts = PerceptLog(world: world)
        let ingress = PersonUtteranceIngressService(
            repository: persistence.conversations, sink: percepts,
            addresseeResolver: FlockResolver(
                rule: LeadAddresseeRule(lead: beaky), present: ["beaky": beaky, "mango": mango]))
        let desk = WhisperDesk(
            event: { try await persistence.events.event(withID: $0) },
            whisperedTo: { try await persistence.conversations.whisperedTo(utterance: $0) })
        let now = self.now
        func say(_ text: String, minute: Double) async throws -> UtteranceIngressResult {
            try await ingress.ingest(
                try PersonUtterance(
                    conversationID: conversationID, speakerID: april, addresseeIDs: [beaky],
                    text: text, modality: .typed, source: .communicatorComposition,
                    sourceID: SourceID(validating: "communicator:test"),
                    occurredAt: now.addingTimeInterval(minute * 60), confidence: 1),
                context: UtteranceIngressContext(boundary: .trustedLAN))
        }
        func keep(
            _ predicate: String, _ value: String, answering said: UtteranceIngressResult,
            by bird: String, claiming claim: String? = nil
        ) async throws {
            let cause = try #require(await percepts.event(of: said.percept.utterance.utteranceID))
            var payload: [String: WorldJSONValue] = [
                "subject_id": .string(april.rawValue), "predicate": .string(predicate),
                "value": .string(value),
            ]
            if let claim { payload[GivenFactAnnouncement.aloneWithKey] = .string(claim) }
            _ = try await world.accept(
                try await desk.mark(
                    try WorldEventEnvelope(
                        type: GivenFactAnnouncement.eventType,
                        occurredAt: said.percept.utterance.occurredAt.addingTimeInterval(1),
                        source: EventSource(
                            id: SourceID(validating: "mind:\(bird)"), kind: "mind",
                            sourceEventID: UUID().uuidString),
                        subjectIDs: [april],
                        epistemic: EpistemicState(type: .reported, confidence: 1),
                        payload: payload, causedBy: [.event(cause)])))
        }

        let whisper = try await say("@beaky this week at work was a long one", minute: 0)
        try await keep("work.week", "a long one", answering: whisper, by: "beaky")
        let room = try await say("Beaky, the deck is finished", minute: 1)
        try await keep("deck.state", "finished", answering: room, by: "beaky")
        // A mind's own mark is never taken on its word: the World's is the only one.
        try await keep(
            "deck.color", "cedar", answering: room, by: "mango", claiming: "character:mango")

        func current() async throws -> [String: Fact] {
            Dictionary(
                uniqueKeysWithValues: try await persistence.facts.currentFacts(subjectID: april)
                    .map { ($0.predicate, $0) })
        }
        let kept = try await current()
        #expect(kept["work.week"]?.aloneWith == beaky)
        #expect(kept["deck.state"]?.aloneWith == nil)
        #expect(kept["deck.color"]?.aloneWith == nil)

        // Each bird's own knowledge: the room's, and its own whispers.
        func predicates(_ facts: [Fact]) -> Set<String> {
            Set(facts.filter { $0.subjectID == april }.map(\.predicate))
        }
        let all: Set = ["work.week", "deck.state", "deck.color"]
        let roomOnly: Set = ["deck.state", "deck.color"]
        for (mind, expected) in [(beaky, all), (mango, roomOnly), (nil, roomOnly)] {
            #expect(
                predicates(
                    try await persistence.facts.heard(by: mind).currentFacts(
                        about: [april], limit: 50, at: now.addingTimeInterval(600)))
                    == expected)
        }
        // The page and the story a mind is handed.
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: ManualWorldClock(now: now.addingTimeInterval(600)))
        for (mind, expected) in [(beaky, all), (mango, roomOnly)] {
            let page = try await knowledge.page(about: [mind, april], mentionedIn: nil, limit: 30)
            #expect(predicates(page.facts) == expected)
            let story = try await knowledge.recentHappenings(
                about: [mind, april], since: now.addingTimeInterval(-60), limit: 50)
            #expect(story.filter { $0.subjectID == april }.count == expected.count)
        }
        // The day's record: marked, and each bird's own is what it heard.
        let digest = try #require(
            try await DayDigestBuilder(
                persistence: persistence, houseConversation: conversationID,
                memory: MemoryConfiguration(timeZone: "America/Los_Angeles")
            ).digest(of: Self.day(of: now)))
        func learned(_ day: DayDigest) -> [String] {
            day.learned.filter { $0.text.hasPrefix(april.rawValue) }.map(\.text).sorted()
        }
        #expect(
            digest.learned.first { $0.text.contains("work.week") }?.aloneWith == beaky)
        #expect(learned(digest.heard(by: mango)).allSatisfy { !$0.contains("work.week") })
        #expect(learned(digest.heard(by: beaky)).contains { $0.contains("work.week") })

        // The past: as kept before 0.64.3, with no mark, then marked by the migration.
        let database = persistence.database
        _ = try await database[MongoWorldCollection.facts].updateMany(
            where: ["subject_id": april.rawValue],
            to: ["$unset": [FactRepository.aloneWithField: ""] as Document])
        _ = try await database[MongoWorldCollection.events].updateMany(
            where: [
                "subject_ids": april.rawValue, "type": GivenFactAnnouncement.eventType.rawValue,
            ],
            to: ["$unset": ["payload.\(GivenFactAnnouncement.aloneWithKey)": ""] as Document])
        #expect(try await current().values.allSatisfy { $0.aloneWith == nil })

        #expect(
            try await MongoWorldMigrator(
                database: database, logger: Logger(label: "whispered-facts-tests")
            ).markWhisperedFacts() >= 1)

        let marked = try await current()
        #expect(marked["work.week"]?.aloneWith == beaky)
        #expect(marked["deck.state"]?.aloneWith == nil)
        let keepingID = try #require(
            marked["work.week"]?.derivedFrom.compactMap { reference -> EventID? in
                if case .event(let id) = reference { return id }
                return nil
            }.first)
        let keeping = try #require(try await persistence.events.event(withID: keepingID))
        #expect(GivenFactAnnouncement.aloneWith(in: keeping) == beaky)
    }
}

extension WhisperedFactsMongoTests {
    /// `now`'s day in the house's zone: the day record's key.
    fileprivate static func day(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// The percepts as the World logs them: what a mind's keeping is caused by.
private actor PerceptLog: PersonUtterancePerceptSink {
    let world: World
    private var events: [UtteranceID: EventID] = [:]

    init(world: World) { self.world = world }

    func event(of utteranceID: UtteranceID) -> EventID? { events[utteranceID] }

    func submit(_ percept: PersonUtterancePercept) async throws -> UtterancePerceptAcceptance {
        let utterance = percept.utterance
        let envelope = try WorldEventEnvelope(
            occurredAt: utterance.occurredAt,
            source: EventSource(
                id: utterance.sourceID, kind: utterance.source.rawValue,
                sourceEventID: utterance.utteranceID.rawValue),
            subjectIDs: [utterance.speakerID, percept.characterID],
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: percept)
        _ = try await world.accept(envelope)
        events[utterance.utteranceID] = envelope.eventID
        return .accepted
    }
}

private struct FlockResolver: AddresseeResolving {
    let rule: LeadAddresseeRule
    let present: [String: EntityID]

    func addressee(for utterance: PersonUtterance, hinted: EntityID) async throws -> Addressee {
        rule.addressee(in: utterance.text, present: present)
    }
}

private struct AcceptingSink: PersonUtterancePerceptSink, CharacterDeliverySink {
    func submit(_ percept: PersonUtterancePercept) async throws -> UtterancePerceptAcceptance {
        .accepted
    }

    func deliver(_ intent: CharacterUtteranceIntent, decision: CharacterDeliveryDecision)
        async throws -> DeliverySinkResult
    {
        DeliverySinkResult(state: .accepted)
    }
}

private struct AtHome: PersonPresenceProviding {
    let april: EntityID
    let now: Date

    func presence(for personID: EntityID) async throws -> PersonPresence {
        try PersonPresence(
            personID: april, state: .home, confidence: 0.98,
            observedAt: now.addingTimeInterval(-10), validUntil: now.addingTimeInterval(600),
            physicallyAudible: true, placeID: EntityID(validating: "place:workshop"))
    }
}

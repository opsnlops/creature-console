import Foundation
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = TestDatabase.uri

@Suite(
    "Evidence over assumption",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct HousePresenceTests {
    @Test("The router reads an observed presence when the house has one, and assumes otherwise")
    func observedPresenceWins() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let april = try EntityID(validating: "person:april-\(UUID().uuidString.lowercased())")
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let assumptions = PresenceConfiguration(
            assumed: [april: try .init(state: .home, physicallyAudible: true, confidence: 0.9)])
        let provider = FactBackedPresenceProvider(
            facts: persistence.facts,
            fallback: AssumedPresenceProvider(configuration: assumptions, clock: clock),
            assumptions: assumptions, clock: clock)

        let assumed = try await provider.presence(for: april)
        #expect(assumed.basis == .assumed)
        #expect(assumed.state == .home)

        // The house saw April leave.
        try await persistence.facts.save(
            try Fact(
                subjectID: april, predicate: WorldFacts.personState, value: .string("away"),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: start.addingTimeInterval(-60), derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))

        let observed = try await provider.presence(for: april)
        #expect(observed.basis == .observed)
        #expect(observed.state == .away)
        #expect(observed.physicallyAudible == false)
        #expect(
            observed.validUntil == start.addingTimeInterval(FactBackedPresenceProvider.validity))
    }

    @Test(
        "A restart's announcement, its marker expired, never lays the old assumption over evidence (#259)"
    )
    func restartKeepsEvidence() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let april = try EntityID(validating: "person:april-\(UUID().uuidString.lowercased())")
        // 13 September, as on the live world.
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [AssumedPersonPresenceReducer(), HouseReducer()], clock: clock)
        let assumptions = PresenceConfiguration(
            assumed: [april: try .init(state: .home, physicallyAudible: true, confidence: 0.9)])
        // The first start announces the assumption.
        let announced = try #require(
            try AssumedPresenceAnnouncement.events(for: assumptions, at: start).first)
        _ = try await world.accept(announced)

        // Five weeks on, the house sees her leave.
        try await clock.advance(by: 35 * 86_400)
        _ = try await world.accept(
            try WorldEventEnvelope(
                type: HouseEvents.personLeft, occurredAt: await clock.now,
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:person-april"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [april], epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: ["entity_id": .string("person.april")]))
        func state() async throws -> Fact? {
            try await persistence.facts.currentFacts(subjectID: april, at: await clock.now)
                .first { $0.predicate == WorldFacts.personState }
        }
        let left = try #require(try await state())
        #expect(left.value == .string("away") && left.epistemic.type == .observed)

        // A deploy: the same announcement again. Its marker has long expired (the TTL keeps
        // a week); the event itself is kept ninety days.
        try await clock.advance(by: 60)
        _ = try await persistence.database[MongoWorldCollection.eventProcessing].deleteOne(
            where: ["_id": announced.eventID.rawValue])
        let again = try #require(
            try AssumedPresenceAnnouncement.events(for: assumptions, at: await clock.now).first)
        let acceptance = try await world.accept(again)
        #expect(acceptance.disposition == .duplicateSourceEvent)

        // She is still away, as the house saw; nothing replaced it.
        #expect(try await state()?.factID == left.factID)
    }

    @Test("A scene ask goes to the house and comes back as the fact the mind is told")
    func sceneAskBecomesARequest() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let house = try EntityID(validating: "house:\(suffix)")
        // Scene names unique to this run: the shared database holds other houses' lists.
        let scene = "Evening \(suffix)"
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [HouseReducer()], clock: clock)
        try await persistence.facts.save(
            try Fact(
                subjectID: house, predicate: WorldFacts.houseScenes,
                value: .array([.string(scene), .string("Bedtime \(suffix)")]),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: start, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))
        let requests = HouseSceneRequests(
            facts: persistence.facts, world: world, clock: clock,
            logger: .init(label: "house-presence-tests"))
        let utterance = try PersonUtterance(
            conversationID: ConversationID(validating: "conversation:april-house"),
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Beaky, set the lights to \(scene)", modality: .typed,
            source: .communicatorComposition, sourceID: SourceID(validating: "communicator:test"),
            occurredAt: start, confidence: 1)

        let fact = try #require(try await requests.request(in: utterance))

        #expect(fact.subjectID == house)
        #expect(fact.predicate == WorldFacts.houseSceneRequested)
        #expect(fact.value == .string(scene))
        #expect(fact.validTo == start.addingTimeInterval(HouseSceneRequests.requestLifetime))
        guard case .event(let eventID)? = fact.derivedFrom.first else {
            Issue.record("the fact should come from the request event")
            return
        }
        let request = try #require(try await persistence.events.event(withID: eventID))
        #expect(request.type == HouseEvents.sceneRequested)
        #expect(request.payload["scene"] == .string(scene))
        #expect(request.source.sourceEventID == utterance.utteranceID.rawValue)
        // Not an ask: nothing happens.
        var mention = utterance
        mention.text = "I love an evening \(suffix)"
        #expect(try await requests.request(in: mention) == nil)
    }

    @Test("A mind may ask the house only when it decides, only for an offered scene (#240)")
    func aMindAsksTheHouse() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let house = try EntityID(validating: "house:\(suffix)")
        let scene = "Movie Time \(suffix)"
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        try await persistence.facts.save(
            try Fact(
                subjectID: house, predicate: WorldFacts.houseScenes,
                value: .array([.string(scene)]),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: start, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))
        func request(_ asked: String, from kind: String = "mind") throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: HouseEvents.sceneRequested, occurredAt: start,
                source: EventSource(
                    id: SourceID(
                        validating: kind == "mind" ? "mind:beaky" : "world:house-commands"),
                    kind: kind, sourceEventID: "response:\(suffix):house"),
                subjectIDs: [house], epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: ["scene": .string(asked)], causedBy: [])
        }
        let mind = HouseAskDesk(
            mode: .mind, facts: persistence.facts, notes: persistence.houseScenes, clock: clock)
        let words = HouseAskDesk(
            mode: .words, facts: persistence.facts, notes: persistence.houseScenes, clock: clock)

        // What a mind is told.
        #expect(try await mind.asks().askedBy == .mind)
        #expect(try await mind.asks().scenes.contains(scene))
        #expect(try await words.asks() == HouseAsks(askedBy: .words, scenes: []))
        // Any spelling of an offered scene is that scene, as the house names it.
        let checked = try await mind.check(try request("movie  TIME \(suffix.uppercased())"))
        #expect(checked.payload["scene"] == .string(scene))
        // Not offered, or the world decides by its words: refused.
        await #expect(throws: WorldContractError.self) {
            try await mind.check(try request("Disco \(suffix)"))
        }
        await #expect(throws: WorldContractError.self) {
            try await words.check(try request(scene))
        }
        // The world's own word rule is never stopped by it.
        let own = try request(scene, from: "world")
        #expect(try await words.check(own) == own)
    }

    @Test("Scenes are described from drafts, April's word wins, and a set-aside scene is refused")
    func scenesAreDescribed() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "house-presence-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let house = try EntityID(validating: "house:\(suffix)")
        let sleepy = "Sleepy Time \(suffix)"
        let carport = "Carport Motion \(suffix)"
        let gone = "Old Party \(suffix)"
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        try await persistence.facts.save(
            try Fact(
                subjectID: house, predicate: WorldFacts.houseScenes,
                value: .array([.string(sleepy), .string(carport)]),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: start, derivedFrom: [],
                producer: FactProducer(kind: "reducer", id: "house", version: "1")))
        let notes = persistence.houseScenes
        try await notes.seed(
            [
                sleepy: HouseSceneDraft(description: "dims the outside lights"),
                carport: HouseSceneDraft(description: "an automation's", askable: false),
                gone: HouseSceneDraft(description: "no longer in the house"),
            ], at: start)
        let desk = HouseAskDesk(mode: .mind, facts: persistence.facts, notes: notes, clock: clock)

        // The page: every offered scene with its note, and the noted one the house dropped.
        let page = try await desk.scenes().scenes.filter { $0.name.hasSuffix(suffix) }
        #expect(page.map(\.name) == [carport, gone, sleepy])
        #expect(page.first { $0.name == gone }?.offered == false)
        #expect(page.first { $0.name == sleepy }?.updatedBy == HouseSceneRepository.draftEditor)
        // A bird is told only what it may ask for, with what it does.
        let asks = try await desk.asks()
        #expect(asks.scenes.contains(sleepy))
        #expect(!asks.scenes.contains(carport))
        #expect(!asks.scenes.contains(gone))
        #expect(asks.descriptions[sleepy] == "dims the outside lights")
        // And may not ask for one set aside.
        let ask = try WorldEventEnvelope(
            type: HouseEvents.sceneRequested, occurredAt: start,
            source: EventSource(
                id: SourceID(validating: "mind:beaky"), kind: "mind",
                sourceEventID: "response:\(suffix):house"),
            subjectIDs: [house], epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: ["scene": .string(carport)], causedBy: [])
        await #expect(throws: WorldContractError.self) { try await desk.check(ask) }

        // A changed draft replaces a draft; April's word is never replaced by one.
        _ = try await notes.set(
            sleepy,
            HouseSceneUpdate(
                description: "outside only, for the neighbors", askable: true,
                updatedBy: "wizard:april"), at: start)
        try await notes.seed(
            [
                sleepy: HouseSceneDraft(description: "a newer draft"),
                carport: HouseSceneDraft(description: "lights the carport", askable: false),
            ], at: start.addingTimeInterval(60))
        let stored = try await notes.all()
        #expect(stored[sleepy]?.description == "outside only, for the neighbors")
        #expect(stored[sleepy]?.updatedBy == "wizard:april")
        #expect(stored[carport]?.description == "lights the carport")
    }
}

@Suite(
    "The story behind the facts",
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests"))
struct RecentHappeningsTests {
    @Test("A mind is told what just happened around its region's places, in order, in words")
    func happeningsAroundTheRegion() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "happenings-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let region = try EntityID(validating: "region:\(suffix)")
        let beaky = try EntityID(validating: "character:beaky-\(suffix)")
        let frontDoor = try EntityID(validating: "place:front-door-\(suffix)")
        let carport = try EntityID(validating: "place:carport-\(suffix)")
        let outside = try EntityID(validating: "place:outside-\(suffix)")
        let jesse = try EntityID(validating: "person:jesse-\(suffix)")
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let sessions = CharacterSessionService(
            repository: persistence.characterSessions, clock: clock, announce: { _ in })
        _ = try await sessions.login(
            beaky,
            CharacterLoginRequest(
                regionID: region, instance: CharacterMindInstance(host: "test", processID: 1)))
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: sessions,
            regions: [
                region: RegionConfiguration(stageID: "s", places: [frontDoor, carport, outside])
            ],
            clock: clock)

        func house(
            _ type: WorldEventType, _ subject: EntityID, at offset: TimeInterval,
            payload: [String: WorldJSONValue] = [:]
        ) throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: type, occurredAt: start.addingTimeInterval(offset),
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:\(suffix)"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [subject], placeID: subject,
                epistemic: EpistemicState(type: .observed, confidence: 1), payload: payload)
        }
        // Out of order on purpose: the story comes back by when it happened.
        let events = [
            try house(HouseEvents.personSeen, carport, at: -20),
            try house(HouseEvents.doorUnlocked, frontDoor, at: -300),
            try house(HouseEvents.measurementChanged, outside, at: -100),  // state, not story
            try house(HouseEvents.doorUnlocked, frontDoor, at: -3_600),  // too old
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: start.addingTimeInterval(-200),
                source: EventSource(
                    id: try SourceID(validating: "wizard:april"), kind: "person",
                    sourceEventID: UUID().uuidString),
                subjectIDs: [jesse], epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(jesse.rawValue),
                    "predicate": .string(WorldFacts.visitorExpected),
                    "value": .string("this afternoon"),
                ]),
        ]
        for event in events {
            _ = try await persistence.events.append(event, receivedAt: start)
        }

        let story = try await knowledge.recentHappenings(
            about: [beaky, jesse], since: start.addingTimeInterval(-900), limit: 10)

        #expect(
            story.map(\.type) == [
                HouseEvents.doorUnlocked, GivenFactAnnouncement.eventType, HouseEvents.personSeen,
            ])
        #expect(story[0].subjectID == frontDoor)
        #expect(story[0].summary?.hasPrefix("The front door") == true)
        #expect(story[0].summary?.hasSuffix("was just unlocked.") == true)
        #expect(
            story[1].summary
                == "wizard:april told the world: \(jesse.rawValue) visitor.expected = \"this afternoon\""
        )
        #expect(story[2].summary?.hasPrefix("A person was just seen at the carport") == true)
        #expect(story[2].occurredAt == start.addingTimeInterval(-20))
        // A limit keeps the newest of the story.
        let latest = try await knowledge.recentHappenings(
            about: [beaky], since: start.addingTimeInterval(-900), limit: 1)
        #expect(latest.map(\.type) == [HouseEvents.personSeen])
    }

    @Test("A day's digest gathers what the house saw, what was said, the scenes, and what was cast")
    func dayDigest() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "digest-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let conversation = try ConversationID(validating: "conversation:digest-\(suffix)")
        let driveway = try EntityID(validating: "place:driveway-\(suffix)")
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-09-13 12:00 PDT
        let noon = Date(timeIntervalSince1970: 1_789_326_000)
        let memory = MemoryConfiguration(timeZone: zone.identifier)

        _ = try await persistence.events.append(
            try WorldEventEnvelope(
                type: HouseEvents.vehicleSeen, occurredAt: noon,
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:\(suffix)"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [driveway], placeID: driveway,
                epistemic: EpistemicState(type: .observed, confidence: 1), payload: [:]),
            receivedAt: noon)
        _ = try await persistence.events.append(
            try WorldEventEnvelope(
                type: HouseEvents.measurementChanged, occurredAt: noon,
                source: EventSource(
                    id: try SourceID(validating: "home-assistant:\(suffix)"),
                    kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                subjectIDs: [driveway], epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: [:]),
            receivedAt: noon)
        try await persistence.conversations.saveConversationItem(
            ConversationItem(
                itemID: .generated(), conversationID: conversation,
                authorID: try EntityID(validating: "person:april"), authorKind: .person,
                text: "Jesse's here to finish the deck.", createdAt: noon.addingTimeInterval(60),
                utteranceID: .generated()))
        let builder = DayDigestBuilder(
            persistence: persistence, houseConversation: conversation, memory: memory)

        let digest = try #require(try await builder.digest(of: "2026-09-13"))
        #expect(digest.day == "2026-09-13")
        #expect(
            digest.happenings.contains {
                $0.type == HouseEvents.vehicleSeen && $0.subjectID == driveway
            })
        // Measurements are state, not story.
        #expect(!digest.happenings.contains { $0.type == HouseEvents.measurementChanged })
        #expect(digest.conversation.map(\.text) == ["Jesse's here to finish the deck."])
        #expect(try await builder.digest(of: "2026-09-12")?.conversation.isEmpty == true)
        #expect(try await builder.digest(of: "not-a-day") == nil)
    }

    @Test(
        "The day's learned facts are what a memory could be about: no body readings, no heartbeats, values as JSON"
    )
    func dayDigestLearned() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "digest-learned-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let conversation = try ConversationID(validating: "conversation:digest-\(suffix)")
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-08-30 12:00 PDT: a day of its own, so other runs' facts are not in it.
        let noon = Date(timeIntervalSince1970: 1_788_116_400)
        let memory = MemoryConfiguration(timeZone: zone.identifier)
        func given(
            _ subject: String, _ predicate: String, _ value: WorldJSONValue, source: String,
            kind: String, at: Date
        ) throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: at,
                source: EventSource(
                    id: try SourceID(validating: source), kind: kind,
                    sourceEventID: UUID().uuidString),
                subjectIDs: [try EntityID(validating: subject)],
                epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(subject), "predicate": .string(predicate),
                    "value": value,
                ])
        }
        let order = try EntityID(validating: "order:amazon-\(suffix)")
        for event in [
            // A body's reading, every thirty seconds all day: state, never a memory.
            try given(
                "character:beaky", "body.power_w", .number(4.2), source: "body:sensors-\(suffix)",
                kind: "body", at: noon),
            try given(
                "thing:creature-server", "server.counters",
                .object(["websocket_messages_sent": .number(12)]),
                source: "body:sensors-\(suffix)", kind: "body", at: noon + 30),
            // The Bridge saying it is alive.
            try given(
                "thing:information-bridge", "bridge.online", .bool(true),
                source: "bridge:app-\(suffix)", kind: "bridge", at: noon + 60),
            // The mail: a memory could be about this.
            try given(
                order.rawValue, "order.items", .string("toothpaste"),
                source: "bridge:mail-\(suffix)", kind: "bridge", at: noon + 120),
            // A mind's own word, with a value that is not text.
            try given(
                "person:april", "person.tools", .array([.string("soldering iron")]),
                source: "mind:beaky-\(suffix)", kind: "mind", at: noon + 180),
            // The calendar's year-ahead window moving on a day: next year's lesson is not
            // news about today (#208); next week's is. Its raw time is the world's own, as the
            // Bridge marks it (#244), so its title is the line.
            try given(
                "event:lessons-\(suffix)-20270830", WorldFacts.calendarStartsAt,
                .string("2027-08-30T23:00:00.000Z"), source: "bridge:calendar-\(suffix)",
                kind: "bridge", at: noon + 240),
            try given(
                "event:lessons-\(suffix)-20270830", "calendar.title", .string("Flight School"),
                source: "bridge:calendar-\(suffix)", kind: "bridge", at: noon + 240),
            try given(
                "event:lessons-\(suffix)-20260906", WorldFacts.calendarStartsAt,
                .string("2026-09-06T23:00:00.000Z"), source: "bridge:calendar-\(suffix)",
                kind: "bridge", at: noon + 300),
            try given(
                "event:lessons-\(suffix)-20260906", "calendar.title", .string("Flight School"),
                source: "bridge:calendar-\(suffix)", kind: "bridge", at: noon + 300),
            // A mind's memory of the day before, written that night: its own, not news (#242).
            try given(
                "person:april", "memory.episode.beaky.2026-08-29.1",
                .object(["what": .string("April soldered all evening")]),
                source: "mind:beaky-\(suffix)", kind: "mind", at: noon + 360),
            // The forecast, restated all day: only its last word stays (#242).
            try given(
                "place:outside", "forecast.next_rain", .string("this afternoon"),
                source: "bridge:weather-\(suffix)", kind: "bridge", at: noon + 420),
            try given(
                "place:outside", "forecast.next_rain", .string("this evening"),
                source: "bridge:weather-\(suffix)", kind: "bridge", at: noon + 480),
            // A mind changing its word is kept every time.
            try given(
                "person:jesse", "visitor.expected", .string("this afternoon"),
                source: "mind:mango-\(suffix)", kind: "mind", at: noon + 540),
            try given(
                "person:jesse", "visitor.expected", .string("here now"),
                source: "mind:mango-\(suffix)", kind: "mind", at: noon + 600),
        ] {
            _ = try await persistence.events.append(event, receivedAt: event.occurredAt)
        }
        _ = try await persistence.factKinds.set(
            WorldFacts.calendarStartsAt, meaning: "when it starts", audience: .world,
            by: "bridge:calendar", at: noon)
        let builder = DayDigestBuilder(
            persistence: persistence, houseConversation: conversation, memory: memory)
        let digest = try #require(try await builder.digest(of: "2026-08-30"))
        let mine = digest.learned.filter { $0.who.hasSuffix(suffix) }
        #expect(
            mine.map(\.text) == [
                "\(order.rawValue) order.items = toothpaste",
                "person:april person.tools = [\"soldering iron\"]",
                "event:lessons-\(suffix)-20260906 calendar.title = Flight School",
                "place:outside forecast.next_rain = this evening",
                "person:jesse visitor.expected = this afternoon",
                "person:jesse visitor.expected = here now",
            ])
        // And a body's reading is not a happening either; nor is any cast fact - `learned`
        // carries each once (#242).
        #expect(!digest.happenings.contains { $0.subjectID.rawValue == "thing:creature-server" })
        #expect(!digest.happenings.contains { $0.type == GivenFactAnnouncement.eventType })
    }

    @Test("The day's record is the minds' view: no world-only kind reaches it (#244)")
    func dayDigestLeavesOutWorldOnlyKinds() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "digest-world-only-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let conversation = try ConversationID(validating: "conversation:digest-\(suffix)")
        // 2026-08-31 12:00 PDT
        let noon = Date(timeIntervalSince1970: 1_788_202_800)
        let memory = MemoryConfiguration(timeZone: "America/Los_Angeles")
        let dentist = "place:dentist-\(suffix)"
        let phone = "contact.phone-\(suffix)"
        _ = try await persistence.factKinds.set(
            phone, meaning: "a phone number", audience: .world, by: "bridge:contacts", at: noon)
        func given(
            _ subject: String, _ predicate: String, _ value: WorldJSONValue, source: String,
            kind: String, at: Date
        ) throws -> WorldEventEnvelope {
            try WorldEventEnvelope(
                type: GivenFactAnnouncement.eventType, occurredAt: at,
                source: EventSource(
                    id: try SourceID(validating: source), kind: kind,
                    sourceEventID: UUID().uuidString),
                subjectIDs: [try EntityID(validating: subject)],
                epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: [
                    "subject_id": .string(subject), "predicate": .string(predicate),
                    "value": value,
                ])
        }
        for event in [
            // April tells Beaky where she is: the minds' own word.
            try given(
                "person:april", "presence.place", .string(dentist), source: "mind:beaky-\(suffix)",
                kind: "mind", at: noon),
            // The World pins the place where her phone is: world-only by its nature.
            try given(
                dentist, WorldFacts.placeGeo,
                .object([
                    "type": .string("Point"), "coordinates": .array([.number(-100), .number(40)]),
                    "radius_m": .number(75), "fixes": .number(1),
                    "taught_by": .string("mind:beaky"),
                ]), source: "world:places-\(suffix)", kind: "world", at: noon + 4),
            // A contact's number, which the glossary gives the world alone.
            try given(
                "person:jesse", phone, .string("360-555-0100"),
                source: "bridge:contacts-\(suffix)", kind: "bridge", at: noon + 60),
        ] {
            _ = try await persistence.events.append(event, receivedAt: event.occurredAt)
        }

        let digest = try #require(
            try await DayDigestBuilder(
                persistence: persistence, houseConversation: conversation, memory: memory
            ).digest(of: "2026-08-31"))
        #expect(
            digest.learned.filter { $0.who.hasSuffix(suffix) }.map(\.text) == [
                "person:april presence.place = \(dentist)"
            ])
    }

    @Test("A day bigger than one page is read to its end, in order")
    func dayEventsArePaged() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "digest-paging-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let place = try EntityID(validating: "place:paged-\(suffix)")
        // 2026-08-23, a day nothing else writes to.
        let start = Date(timeIntervalSince1970: 1_787_511_600)
        for index in 0..<7 {
            _ = try await persistence.events.append(
                try WorldEventEnvelope(
                    type: HouseEvents.motionDetected, occurredAt: start + Double(index * 60),
                    source: EventSource(
                        id: try SourceID(validating: "home-assistant:\(suffix)"),
                        kind: HouseEvents.sourceKind, sourceEventID: UUID().uuidString),
                    subjectIDs: [place], placeID: place,
                    epistemic: EpistemicState(type: .observed, confidence: 1), payload: [:]),
                receivedAt: start + Double(index * 60))
        }
        let all = try await persistence.events.allEvents(
            from: start, to: start + 3_600, pageSize: 3)
        let mine = all.filter { $0.placeID == place }
        #expect(mine.count == 7)
        #expect(mine.map(\.occurredAt) == mine.map(\.occurredAt).sorted())
        // The capped read that lost the evening would have stopped at three.
        #expect(
            try await persistence.events.events(from: start, to: start + 3_600, limit: 3).count
                == 3)
    }

    @Test("Meanings come from the store, seeded from the catalogue, and a Wizard's word wins")
    func meaningsAreStoredAndEditable() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "fact-kinds-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let start = Date(timeIntervalSince1970: 1_789_600_000)
        let clock = ManualWorldClock(now: start)
        let sessions = CharacterSessionService(
            repository: persistence.characterSessions, clock: clock, announce: { _ in })
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: sessions, regions: [:], clock: clock)
        let predicate = "test.\(UUID().uuidString.lowercased())"

        try await persistence.factKinds.seed([predicate: "from the catalogue"], at: start)
        #expect(try await knowledge.meanings(of: [predicate]) == [predicate: "from the catalogue"])
        // The catalogue answers for a predicate the store has never seen.
        #expect(
            try await knowledge.meanings(of: [WorldFacts.doorLock])[WorldFacts.doorLock]
                == WorldFacts.meanings[WorldFacts.doorLock])

        let reworded = try await persistence.factKinds.set(
            predicate, meaning: "as April puts it", audience: nil, by: "wizard:april",
            at: start + 60)
        #expect(reworded.updatedBy == "wizard:april")
        #expect(reworded.audience == .minds)
        try await persistence.factKinds.seed([predicate: "from the catalogue"], at: start + 120)
        #expect(try await knowledge.meanings(of: [predicate]) == [predicate: "as April puts it"])
        // The catalogue's own words, improved in code, reach a world that holds the old ones;
        // a Wizard's never move.
        let improved = "test.\(UUID().uuidString.lowercased())"
        try await persistence.factKinds.seed([improved: "a bird's pronouns"], at: start)
        try await persistence.factKinds.seed([improved: "anyone's pronouns"], at: start + 180)
        #expect(try await knowledge.meanings(of: [improved]) == [improved: "anyone's pronouns"])
        try await persistence.factKinds.seed([predicate: "catalogue, reworded"], at: start + 240)
        #expect(try await knowledge.meanings(of: [predicate]) == [predicate: "as April puts it"])
        #expect(
            try await persistence.factKinds.all().contains {
                $0.predicate == predicate && $0.meaning == "as April puts it"
            })
        // An audience set once stays through a rewording that says nothing about it.
        let worldOnly = try await persistence.factKinds.set(
            predicate, meaning: "the world's alone", audience: .world, by: "wizard:april",
            at: start + 180)
        #expect(worldOnly.audience == .world)
        let rewordedAgain = try await persistence.factKinds.set(
            predicate, meaning: "still the world's", audience: nil, by: "wizard:april",
            at: start + 240)
        #expect(rewordedAgain.audience == .world)
        #expect(try await persistence.factKinds.worldOnlyPredicates().contains(predicate))
    }

    @Test(
        "An event at the house with a person, within a day, is a visitor expected; gone when cancelled"
    )
    func calendarMakesVisitors() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "visitor-rule-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let jesse = try EntityID(validating: "person:jesse-\(suffix)")
        let visit = try EntityID(validating: "event:deck-\(suffix)")
        let dentist = try EntityID(validating: "event:dentist-\(suffix)")
        func fact(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue) throws
            -> Fact
        {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
                validTo: now.addingTimeInterval(3_600), derivedFrom: [],
                producer: FactProducer(kind: "bridge", id: "calendar", version: "1"))
        }
        // Jesse at the house in three hours; the dentist across town, with nobody April knows.
        let starts = now.addingTimeInterval(3 * 3_600)
        for f in [
            try fact(visit, "calendar.title", .string("Deck boards")),
            try fact(visit, "calendar.when", .string("Thursday, September 17 at 2:00 PM")),
            try fact(visit, "calendar.starts_at", .string(WorldJSON.timestamp(starts))),
            try fact(visit, "calendar.ends_at", .string(WorldJSON.timestamp(starts + 7_200))),
            try fact(visit, "calendar.with", .string(jesse.rawValue)),
            try fact(dentist, "calendar.title", .string("Dentist")),
            try fact(dentist, "calendar.location", .string("Coupeville Dental")),
            try fact(dentist, "calendar.starts_at", .string(WorldJSON.timestamp(starts))),
        ] {
            try await persistence.facts.save(f)
        }
        let accepted = Accepted()
        let rule = VisitorRule(atHome: ["home"], facts: persistence.facts) {
            await accepted.note($0)
        }
        // The shared database holds other runs' calendars: judge this run's events only.
        let visitors = try await rule.sweep(now: now)
        #expect(visitors[visit]?.person == jesse)
        #expect(visitors[dentist] == nil)
        #expect(visitors[visit]?.value == "Thursday, September 17 at 2:00 PM, Deck boards")
        #expect(visitors[visit]?.until == starts + 7_200 + 2 * 3_600)
        let first = await accepted.events.filter { $0.subjectIDs == [jesse] }
        #expect(first.count == 1)
        #expect(first.first?.payload["predicate"] == .string(WorldFacts.visitorExpected))
        #expect(first.first?.source.id == VisitorRule.sourceID)
        // The same calendar again: nothing more to say.
        _ = try await rule.sweep(now: now + 60)
        #expect(await accepted.events.filter { $0.subjectIDs == [jesse] }.count == 1)
        // Two days earlier the visit is not yet a visitor, and the one cast is taken back.
        #expect(try await rule.sweep(now: now - 2 * 86_400)[visit] == nil)
        let last = await accepted.events.last { $0.subjectIDs == [jesse] }
        #expect(last?.payload["value"] == .null)
    }

    @Test(
        "An away event has a leave-by time; near it, with April home, the house speaks - once each")
    func departuresAreOccasions() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "departure-rule-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let house = try EntityID(validating: "house:departures-\(suffix)")
        let training = try EntityID(validating: "event:training-\(suffix)")
        let dinner = try EntityID(validating: "event:dinner-\(suffix)")
        let april = try EntityID(validating: "person:april")
        func fact(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue) throws
            -> Fact
        {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
                validTo: now.addingTimeInterval(3 * 3_600), derivedFrom: [],
                producer: FactProducer(kind: "bridge", id: "calendar", version: "1"))
        }
        // Training in Freeland in 45 minutes (20 to get there: leave by +25); dinner at home.
        let starts = now.addingTimeInterval(45 * 60)
        for f in [
            try fact(training, "calendar.title", .string("Training \(suffix)")),
            try fact(
                training, "calendar.location",
                .string("5522 Freeland Avenue, Freeland, Washington 98249")),
            try fact(training, "calendar.starts_at", .string(WorldJSON.timestamp(starts))),
            try fact(dinner, "calendar.title", .string("Dinner")),
            try fact(dinner, "calendar.location", .string("Home")),
            try fact(dinner, "calendar.starts_at", .string(WorldJSON.timestamp(starts))),
        ] {
            try await persistence.facts.save(f)
        }
        // April is home. (A fact of this test's own house is not enough: presence is hers.)
        try await persistence.facts.save(
            try Fact(
                subjectID: april, predicate: WorldFacts.personState, value: .string("home"),
                epistemic: EpistemicState(type: .observed, confidence: 1), validFrom: now,
                validTo: now.addingTimeInterval(3 * 3_600), derivedFrom: [],
                producer: FactProducer(kind: "house", id: "test-\(suffix)", version: "1")))
        // The sky, as the Bridge casts it - on an outside of this test's own.
        let outside = try EntityID(validating: "place:outside-\(suffix)")
        try await persistence.facts.save(
            try fact(
                outside, "forecast.today", .string("Drizzle, high 63°, low 52°, 46% chance of rain")
            ))
        try await persistence.facts.save(
            try fact(outside, "forecast.next_rain", .string("this afternoon, 46% chance")))
        let accepted = Accepted()
        let rule = DepartureRule(
            configuration: DepartureRuleConfiguration(
                headsUpMinutes: 20, defaultTravelMinutes: 30,
                travel: [.init(words: ["freeland"], minutes: 20)], outside: outside.rawValue),
            atHome: ["home"], house: house, zone: zone, facts: persistence.facts
        ) { await accepted.note($0) }

        // Only this test's training counts: the shared database has other runs' away events.
        func mine() async -> [WorldEventEnvelope] {
            await accepted.events.filter { event in
                event.subjectIDs.contains(training)
                    || {
                        if case .string(let value)? = event.payload["value"] {
                            return value.hasPrefix("Training \(suffix) in Freeland")
                        }
                        return false
                    }()
            }
        }
        // Now: the fact is cast, nothing said yet (leave-by is 25 minutes out, heads-up is 20).
        let inForce = try await rule.sweep(now: now)
        #expect(inForce[training]?.leaveBy == starts.addingTimeInterval(-20 * 60))
        #expect(inForce[dinner] == nil)
        var events = await mine()
        #expect(events.count == 1)
        #expect(events[0].payload["predicate"] == .string("departure.due"))
        #expect(events[0].subjectIDs == [house])
        if case .string(let value)? = events[0].payload["value"] {
            #expect(value.contains("leaving by"))
        } else {
            Issue.record("no departure value")
        }
        // Six minutes on: inside the heads-up. The house speaks once.
        _ = try await rule.sweep(now: now + 6 * 60)
        events = await mine()
        #expect(events.count == 2)
        #expect(events[1].type == HouseEvents.departureSoon)
        _ = try await rule.sweep(now: now + 10 * 60)
        #expect(await mine().count == 2)
        // Leave-by itself: once more.
        _ = try await rule.sweep(now: now + 26 * 60)
        events = await mine()
        #expect(events.count == 3)
        #expect(events[2].type == HouseEvents.departureNow)
        _ = try await rule.sweep(now: now + 30 * 60)
        #expect(await mine().count == 3)
        // The words the birds read - the sky included, "leave ten early, it's pouring" - and
        // the occasion the house makes of them.
        let note = SceneOpeningPolicy.triggerText(for: events[2], place: house)
        #expect(note.hasPrefix("It is time to leave: Training \(suffix) in Freeland at "))
        #expect(
            note.hasSuffix(
                "April is still home. Today: Drizzle, high 63°, low 52°, 46% chance of rain. Rain: this afternoon, 46% chance."
            ))
        #expect(
            events[1].payload["weather"]
                == .string(
                    "Today: Drizzle, high 63°, low 52°, 46% chance of rain. Rain: this afternoon, 46% chance."
                ))
        let policy = SceneOpeningPolicy(rules: [])
        #expect(
            await policy.occasion(for: events[1], at: now + 6 * 60)
                == SceneOpeningPolicy.Occasion(place: house, kind: .houseConsideration))
    }

    @Test(
        "An order out for delivery is a delivery expected at the house; a question finds it by its items"
    )
    func ordersMakeDeliveries() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "delivery-rule-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        // A word of this run's own, so the shared database's other runs never crowd it out.
        let word =
            "gizmo" + String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let order = try EntityID(validating: "order:adafruit-\(suffix)")
        func fact(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue) throws
            -> Fact
        {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: now,
                validTo: now.addingTimeInterval(3_600), derivedFrom: [],
                producer: FactProducer(kind: "bridge", id: "mail", version: "1"))
        }
        for f in [
            try fact(order, "order.merchant", .string("Adafruit")),
            try fact(order, "order.items", .array([.string("\(word.capitalized) Kit ×4")])),
            try fact(order, "order.carrier", .string("UPS")),
            try fact(order, "order.status", .string("out_for_delivery")),
            try fact(order, "order.updated_at", .string(WorldJSON.timestamp(now - 3_600))),
        ] {
            try await persistence.facts.save(f)
        }
        // An old order read back today is not at the door: the mail's date decides.
        let stale = try EntityID(validating: "order:old-\(suffix)")
        for f in [
            try fact(stale, "order.status", .string("delivered")),
            try fact(stale, "order.updated_at", .string(WorldJSON.timestamp(now - 90 * 86_400))),
        ] {
            try await persistence.facts.save(f)
        }
        let accepted = Accepted()
        let rule = DeliveryRule(
            house: try EntityID(validating: "house:aprils-nest"), facts: persistence.facts,
            zone: TimeZone(identifier: "America/Los_Angeles")!
        ) { await accepted.note($0) }
        let deliveries = try await rule.sweep(now: now)
        #expect(deliveries[order] == "\(word.capitalized) Kit ×4 (UPS), today")
        #expect(deliveries[stale] == nil)
        let mine = await accepted.events.filter { $0.subjectIDs.contains(order) }
        #expect(mine.count == 1)
        #expect(mine.first?.payload["predicate"] == .string("delivery.expected"))
        #expect(mine.first?.payload["subject_id"] == .string("house:aprils-nest"))
        // Said once; the next sweep says nothing more.
        _ = try await rule.sweep(now: now + 60)
        #expect(await accepted.events.filter { $0.subjectIDs.contains(order) }.count == 1)

        // "Did I order a servo?" finds the order by what was in it.
        let clock = ManualWorldClock(now: now)
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        let handed = try await knowledge.currentFacts(
            about: [], mentionedIn: "Beaky, did I order a \(word)?",
            limit: WorldKnowledgeLimits.maximumFacts)
        try await expectPageCovers(
            knowledge, about: [], words: "Beaky, did I order a \(word)?", checking: [order])
        #expect(handed.contains { $0.subjectID == order && $0.predicate == "order.items" })
        let unrelated = try await knowledge.currentFacts(
            about: [], mentionedIn: "is it raining?", limit: WorldKnowledgeLimits.maximumFacts)
        #expect(!unrelated.contains { $0.subjectID == order })
        // "Did I order anything?" names nothing in the order, but the order is news - the mail
        // spoke of it an hour ago - so it is handed over; the ninety-day-old one is not.
        let anything = try await knowledge.currentFacts(
            about: [], mentionedIn: "did I just order anything?",
            limit: WorldKnowledgeLimits.maximumFacts)
        try await expectPageCovers(
            knowledge, about: [], words: "did I just order anything?", checking: [order])
        #expect(anything.contains { $0.subjectID == order && $0.predicate == "order.items" })
        #expect(!anything.contains { $0.subjectID == stale })
    }

    @Test("Orders the mail has finished with become history: three days delivered, two weeks quiet")
    func ordersSettle() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "delivery-rule-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let suffix = UUID().uuidString.lowercased()
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let clock = ManualWorldClock(now: now)
        let world = World(
            eventStore: persistence.events, factStore: persistence.facts,
            reducers: [OrderReducer()], clock: clock)
        func order(_ name: String, _ status: String, heard daysAgo: Double) async throws
            -> EntityID
        {
            let id = try EntityID(validating: "order:\(name)-\(suffix)")
            for (predicate, value) in [
                ("order.merchant", WorldJSONValue.string("Adafruit")),
                ("order.status", .string(status)),
                (
                    "order.updated_at",
                    .string(WorldJSON.timestamp(now - daysAgo * 86_400))
                ),
            ] {
                try await persistence.facts.save(
                    try Fact(
                        subjectID: id, predicate: predicate, value: value,
                        epistemic: EpistemicState(type: .reported, confidence: 1),
                        validFrom: now - 60, validTo: now + 3_600, derivedFrom: [],
                        producer: FactProducer(kind: "bridge", id: "mail", version: "1"),
                        origin: SourceID(validating: "bridge:mail")))
            }
            return id
        }
        let delivered = try await order("delivered", "delivered", heard: 4)
        let justDelivered = try await order("just", "delivered", heard: 1)
        let lost = try await order("lost", "shipped", heard: 20)
        let onTheWay = try await order("way", "shipped", heard: 5)
        let rule = DeliveryRule(
            house: try EntityID(validating: "house:aprils-nest"), facts: persistence.facts,
            zone: TimeZone(identifier: "America/Los_Angeles")!
        ) { _ = try await world.accept($0) }

        let settled = try await rule.settle(now: now)
        #expect(settled.contains(delivered))
        #expect(settled.contains(lost))
        #expect(!settled.contains(justDelivered))
        #expect(!settled.contains(onTheWay))
        // Settled: nothing current on the order; the facts stay on the record as what was.
        for id in [delivered, lost] {
            #expect(try await persistence.facts.currentFacts(subjectID: id, at: now + 5).isEmpty)
        }
        for id in [justDelivered, onTheWay] {
            #expect(
                try await persistence.facts.currentFacts(subjectID: id, at: now + 5).count == 3)
        }
        // Said once: the next pass finds nothing more to settle among these.
        let again = try await rule.settle(now: now + 60)
        #expect(!again.contains(delivered) && !again.contains(lost))
    }

    @Test("A world-only kind never reaches a mind; a link brings the linked entity along")
    func audienceAndLinks() async throws {
        let uri = try #require(mongoTestURI)
        let persistence = try await MongoWorldPersistence.connect(
            to: uri, logger: .init(label: "audience-tests"))
        defer { Task { await persistence.cluster.disconnect() } }
        let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let clock = ManualWorldClock(now: start)
        let suffix = UUID().uuidString.lowercased()
        let visit = try EntityID(validating: "event:deck-\(suffix)")
        let jesse = try EntityID(validating: "person:jesse-\(suffix)")
        let knowledge = PresentWorldKnowledge(
            facts: persistence.facts, events: persistence.events, kinds: persistence.factKinds,
            sessions: CharacterSessionService(
                repository: persistence.characterSessions, clock: clock, announce: { _ in }),
            regions: [:], clock: clock)
        func fact(_ subject: EntityID, _ predicate: String, _ value: WorldJSONValue) throws
            -> Fact
        {
            try Fact(
                subjectID: subject, predicate: predicate, value: value,
                epistemic: EpistemicState(type: .reported, confidence: 1), validFrom: start,
                validTo: start.addingTimeInterval(3_600), derivedFrom: [],
                producer: FactProducer(kind: "test", id: "bridge", version: "1"))
        }
        try await persistence.facts.save(try fact(visit, "calendar.title", .string("deck boards")))
        try await persistence.facts.save(try fact(visit, "calendar.with", .string(jesse.rawValue)))
        try await persistence.facts.save(
            try fact(jesse, "person.relationship", .string("April's contractor")))
        try await persistence.facts.save(
            try fact(jesse, "contact.phone-\(suffix)", .string("360-555-0100")))
        _ = try await persistence.factKinds.set(
            "contact.phone-\(suffix)", meaning: "a phone number", audience: .world,
            by: "bridge:contacts", at: start)

        // "What's on this weekend?" is handed the visit without naming it: the next days of the
        // calendar ride along with every question. The page holds the eight soonest, and the
        // window reaches three hours back for what is under way - the shared database holds
        // other tests' events, some running beside this one - so this visit began just inside
        // that window and sorts first. And the world-only timestamps never take a mind's
        // place on the page.
        try await persistence.facts.save(
            try fact(
                visit, "calendar.starts_at",
                .string(WorldJSON.timestamp(start.addingTimeInterval(-3 * 3_600 + 30)))))
        _ = try await persistence.factKinds.set(
            "calendar.starts_at", meaning: "when it starts", audience: .world,
            by: "bridge:calendar", at: start)
        let weekend = try await knowledge.currentFacts(
            about: [], mentionedIn: "what's on the calendar this weekend?",
            limit: WorldKnowledgeLimits.maximumFacts)
        try await expectPageCovers(
            knowledge, about: [], words: "what's on the calendar this weekend?",
            checking: [visit, jesse])
        // Folded into one line, title first (#232).
        #expect(
            weekend.contains { $0.subjectID == visit && $0.predicate == WorldFacts.calendarEvent })
        #expect(!weekend.contains { $0.subjectID == visit && $0.predicate == "calendar.title" })
        #expect(!weekend.contains { $0.predicate == "calendar.starts_at" })
        #expect(
            Set(weekend.map(\.subjectID).filter { $0.rawValue.hasPrefix("event:") }).count
                <= WorldKnowledgeLimits.maximumUpcomingEvents)

        // Asked about the visit, a mind is handed Jesse too - but never his number.
        let handed = try await knowledge.currentFacts(
            about: [visit], mentionedIn: nil, limit: WorldKnowledgeLimits.maximumFacts)
        #expect(handed.contains { $0.subjectID == jesse && $0.predicate == "person.relationship" })

        // His pronouns ride along whenever he is named, even when the capped page has room
        // for only one of his facts - they are how the birds say his name. Saved older than
        // his relationship, so the one place on the page goes to that.
        var pronouns = try fact(jesse, WorldFacts.pronouns, .string("he/him"))
        pronouns.validFrom = start - 60
        try await persistence.facts.save(pronouns)
        let tight = try await knowledge.currentFacts(about: [jesse], mentionedIn: nil, limit: 1)
        let his = tight.filter { $0.subjectID == jesse }
        #expect(his.contains { $0.predicate == "person.relationship" })
        #expect(
            his.filter { $0.predicate == WorldFacts.pronouns }.map(\.value) == [.string("he/him")])
        #expect(!handed.contains { $0.predicate == "contact.phone-\(suffix)" })
        #expect(handed.contains { $0.predicate == "calendar.with" })

        // The entity page holds everything, and knows what points at Jesse.
        let page = try await knowledge.entityPage(jesse, now: start)
        #expect(page.facts.contains { $0.predicate == "contact.phone-\(suffix)" })
        #expect(page.linkedFrom.map(\.subjectID) == [visit])

        // "My contractor" finds Jesse by what he is to April, with no name in the question.
        try await persistence.facts.save(
            try fact(jesse, WorldFacts.personRelationship, .string("General Contractor")))
        let asked = try await knowledge.currentFacts(
            about: [], mentionedIn: "is my contractor coming today?",
            limit: WorldKnowledgeLimits.maximumFacts)
        try await expectPageCovers(
            knowledge, about: [], words: "is my contractor coming today?", checking: [visit, jesse])
        #expect(asked.contains { $0.subjectID == jesse && $0.predicate == "person.relationship" })
    }
}

private actor Accepted {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}

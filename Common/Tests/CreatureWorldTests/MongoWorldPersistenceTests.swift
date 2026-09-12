import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import MongoKitten
import Testing
import WorldCore

@testable import creature_world

private let mongoTestURI = ProcessInfo.processInfo.environment["MONGODB_TEST_URI"]

@Suite(
    "Creature World MongoDB persistence",
    .serialized,
    .enabled(if: mongoTestURI != nil, "Set MONGODB_TEST_URI to run MongoDB integration tests")
)
struct MongoWorldPersistenceTests {
    @Test("HTTP event acceptance remains queryable after an application restart")
    func httpAcceptanceSurvivesRestart() async throws {
        let uri = try #require(mongoTestURI)
        let configuration = try CreatureWorldConfiguration(mongoURI: uri)
        let event = try makeEvent(sourceEventID: UUID().uuidString.lowercased())
        let requestBody = ByteBuffer(bytes: try WorldJSON.makeEncoder().encode(event))

        let firstDependencies = try await CreatureWorldDependencies.live(
            configuration: configuration,
            logger: Logger(label: "creature-world-http-mongodb-tests"),
            buildInfo: CreatureWorldBuildInfo(version: "http-mongodb-test", schemaVersion: 1)
        )
        let firstApplication = makeCreatureWorldApplication(dependencies: firstDependencies)
        let sequence = try await firstApplication.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/events",
                method: .post,
                headers: [.contentType: "application/json"],
                body: requestBody
            ) { response -> Int64 in
                #expect(response.status == .accepted)
                let result = try WorldJSON.makeDecoder().decode(
                    WorldEventAcceptanceResponse.self,
                    from: response.body
                )
                return try #require(result.event.worldSequence)
            }
        }

        let secondDependencies = try await CreatureWorldDependencies.live(
            configuration: configuration,
            logger: Logger(label: "creature-world-http-mongodb-tests"),
            buildInfo: CreatureWorldBuildInfo(version: "http-mongodb-test", schemaVersion: 1)
        )
        let secondApplication = makeCreatureWorldApplication(dependencies: secondDependencies)
        try await secondApplication.test(.router) { client in
            try await client.execute(
                uri: "/world/v1/events?after_sequence=\(sequence - 1)&limit=10",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try WorldJSON.makeDecoder().decode(
                    WorldEventPage.self,
                    from: response.body
                )
                #expect(page.events.contains { $0.eventID == event.eventID })
            }
        }
    }

    @Test("Migration creates the required repository indexes")
    func createsRequiredIndexes() async throws {
        try await withPersistence { persistence in
            let eventIndexes = try await persistence.database[MongoWorldCollection.events]
                .listIndexes().drain()
            let factIndexes = try await persistence.database[MongoWorldCollection.facts]
                .listIndexes().drain()
            let timerIndexes = try await persistence.database[MongoWorldCollection.timers]
                .listIndexes().drain()
            let ingressIndexes = try await persistence.database[
                MongoWorldCollection.utteranceIngresses
            ].listIndexes().drain()
            let conversationIndexes = try await persistence.database[
                MongoWorldCollection.conversationItems
            ].listIndexes().drain()
            let deliveryIndexes = try await persistence.database[
                MongoWorldCollection.characterDeliveries
            ].listIndexes().drain()

            #expect(eventIndexes.contains { $0.name == "event_id_unique" && $0.unique == true })
            #expect(
                eventIndexes.contains { $0.name == "world_sequence_unique" && $0.unique == true }
            )
            #expect(eventIndexes.contains { $0.name == "source_event_unique" && $0.unique == true })
            #expect(factIndexes.contains { $0.name == "active_facts" })
            #expect(timerIndexes.contains { $0.name == "pending_timers" })
            #expect(
                ingressIndexes.contains { $0.name == "utterance_id_unique" && $0.unique == true }
            )
            #expect(
                conversationIndexes.contains {
                    $0.name == "conversation_item_id_unique" && $0.unique == true
                }
            )
            #expect(conversationIndexes.contains { $0.name == "conversation_order" })
            #expect(
                deliveryIndexes.contains {
                    $0.name == "delivery_attempt_id_unique" && $0.unique == true
                }
            )
            #expect(deliveryIndexes.contains { $0.name == "conversation_responses" })
            let stageIndexes = try await persistence.database[
                MongoWorldCollection.characterStageDecisions
            ].listIndexes().drain()
            #expect(
                stageIndexes.contains {
                    $0.name == "stage_decision_expiry" && $0.expireAfterSeconds == 0
                }
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 6]) != nil
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 5]) != nil
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 4]) != nil
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 1]) != nil
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 2]) != nil
            )
            #expect(
                try await persistence.database[MongoWorldCollection.schemaMigrations]
                    .findOne(["_id": 3]) != nil
            )
        }
    }

    @Test("Conversation ingress is durable, ordered, and idempotent")
    func conversationIngressIsDurableOrderedAndIdempotent() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let conversationID = try ConversationID(validating: "conversation:\(suffix)")
            let first = try makeIngress(
                suffix: "\(suffix)-first",
                conversationID: conversationID,
                occurredAt: Date(timeIntervalSince1970: 1_000)
            )
            let second = try makeIngress(
                suffix: "\(suffix)-second",
                conversationID: conversationID,
                occurredAt: Date(timeIntervalSince1970: 2_000)
            )

            #expect(try await persistence.conversations.prepare(first) == first)
            #expect(try await persistence.conversations.prepare(first) == first)
            #expect(try await persistence.conversations.prepare(second) == second)
            try await persistence.conversations.markPerceptSubmitted(
                utteranceID: first.percept.utterance.utteranceID
            )

            let stored = try #require(
                try await persistence.conversations.ingress(
                    for: first.percept.utterance.utteranceID
                )
            )
            let items = try await persistence.conversations.conversationItems(
                in: conversationID,
                after: nil,
                limit: 10
            )
            #expect(stored.progress == .perceptSubmitted)
            #expect(
                items.map(\.itemID) == [
                    first.conversationItem.itemID, second.conversationItem.itemID,
                ]
            )
        }
    }

    @Test("Beaky's turn is durable, idempotent, and ordered with April's")
    func characterDeliveryIsDurableAndOrdered() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let conversationID = try ConversationID(validating: "conversation:\(suffix)")
            let april = try makeIngress(
                suffix: "\(suffix)-april",
                conversationID: conversationID,
                occurredAt: Date(timeIntervalSince1970: 1_000)
            )
            let beaky = try makeDelivery(
                suffix: "\(suffix)-beaky",
                conversationID: conversationID,
                inResponseTo: april.percept.utterance.utteranceID,
                createdAt: Date(timeIntervalSince1970: 1_005)
            )
            let repository = persistence.characterDeliveries

            #expect(try await repository.delivery(for: beaky.intent.responseID) == nil)
            _ = try await persistence.conversations.prepare(april)
            #expect(try await repository.prepare(beaky) == beaky)
            var conflicting = beaky
            conflicting.intent.text = "Different words under the same response identity"
            #expect(try await repository.prepare(conflicting) == beaky)

            let outcome = CharacterDeliveryOutcome(
                attemptID: beaky.decision.attemptID,
                responseID: beaky.intent.responseID,
                route: beaky.decision.route,
                state: .accepted,
                occurredAt: Date(timeIntervalSince1970: 1_006)
            )
            try await repository.record(outcome)

            let stored = try #require(try await repository.delivery(for: beaky.intent.responseID))
            #expect(stored.intent == beaky.intent)
            #expect(stored.decision == beaky.decision)
            #expect(stored.outcome == outcome)

            let items = try await persistence.conversations.conversationItems(
                in: conversationID,
                after: nil,
                limit: 10
            )
            #expect(items == [april.conversationItem, beaky.conversationItem])
            #expect(items.map(\.authorKind) == [.person, .character])

            // Deliveries page in the order Beaky spoke, by response ID.
            let second = try makeDelivery(
                suffix: "\(suffix)-beaky-2",
                conversationID: conversationID,
                inResponseTo: april.percept.utterance.utteranceID,
                createdAt: Date(timeIntervalSince1970: 1_010)
            )
            _ = try await repository.prepare(second)
            let firstPage = try await repository.deliveries(
                in: conversationID, after: nil, limit: 1)
            #expect(firstPage.map(\.intent.responseID) == [beaky.intent.responseID])
            let rest = try await repository.deliveries(
                in: conversationID, after: beaky.intent.responseID, limit: 10)
            #expect(rest.map(\.intent.responseID) == [second.intent.responseID])
            await #expect(throws: WorldAPIError.invalidQuery(name: "after_response_id")) {
                _ = try await repository.deliveries(
                    in: conversationID, after: .generated(), limit: 10)
            }
        }
    }

    @Test("A stage decision is durable and the first one wins")
    func stageDecisionIsDurable() async throws {
        try await withPersistence { persistence in
            let now = Date(timeIntervalSince1970: 1_789_100_000)
            let responseID = ResponseID.generated()
            let april = try EntityID(validating: "person:april")
            func makeStage(route: CharacterDeliveryRoute) throws -> StoredStageDecision {
                let home = route == .physicalSpeech
                return StoredStageDecision(
                    conversationID: try ConversationID(validating: "conversation:april-beaky"),
                    characterID: try EntityID(validating: "character:beaky"),
                    recipientID: april,
                    decision: try CharacterDeliveryDecision(
                        responseID: responseID,
                        route: route,
                        privacyMode: home ? .notApplicable : .private,
                        reason: home ? .homeAndAudible : .presenceUncertain,
                        decidedAt: now,
                        presence: PersonPresence(
                            personID: april, state: home ? .home : .unknown,
                            confidence: home ? 1 : 0, observedAt: now, validUntil: now,
                            physicallyAudible: home, basis: home ? .assumed : .inferred)
                    ),
                    expiresAt: now.addingTimeInterval(300)
                )
            }

            #expect(try await persistence.characterDeliveries.stageDecision(for: responseID) == nil)
            let first = try await persistence.characterDeliveries.prepareStage(
                makeStage(route: .physicalSpeech))
            let second = try await persistence.characterDeliveries.prepareStage(
                makeStage(route: .communicator))
            let read = try await persistence.characterDeliveries.stageDecision(for: responseID)

            #expect(first.decision.route == .physicalSpeech)
            #expect(second == first)
            #expect(read == first)
            #expect(read?.decision.presence.basis == .assumed)
        }
    }

    @Test("Character sessions are durable and the latest per character is what the world sees")
    func characterSessionsAreDurable() async throws {
        try await withPersistence { persistence in
            let now = Date(timeIntervalSince1970: 1_789_300_000)
            let beaky = try EntityID(validating: "character:\(UUID().uuidString.lowercased())")
            // A region of its own: the shared test database also hosts the black-box service
            // test, whose scenes count whoever is logged into region:home.
            let home = try EntityID(validating: "region:test-\(UUID().uuidString.lowercased())")
            let older = try CharacterSession(
                characterID: beaky, regionID: home,
                instance: CharacterMindInstance(host: "fuzzball", processID: 1),
                state: .loggedOut, loggedInAt: now, lastHeartbeatAt: now,
                expiresAt: now.addingTimeInterval(30), endedAt: now.addingTimeInterval(10))
            let newer = try CharacterSession(
                characterID: beaky, regionID: home,
                instance: CharacterMindInstance(host: "fuzzball", processID: 2),
                loggedInAt: now.addingTimeInterval(60), lastHeartbeatAt: now.addingTimeInterval(60),
                expiresAt: now.addingTimeInterval(90))

            try await persistence.characterSessions.save(older)
            try await persistence.characterSessions.save(newer)
            var renewed = newer
            renewed.expiresAt = now.addingTimeInterval(120)
            try await persistence.characterSessions.save(renewed)

            #expect(try await persistence.characterSessions.session(for: beaky) == renewed)
            #expect(try await persistence.characterSessions.session(id: older.sessionID) == older)
            let latest = try await persistence.characterSessions.latestSessions()
            #expect(latest.filter { $0.characterID == beaky } == [renewed])
        }
    }

    @Test("Recording an outcome for an unknown Beaky turn fails explicitly")
    func recordingUnknownDeliveryFails() async throws {
        try await withPersistence { persistence in
            let outcome = CharacterDeliveryOutcome(
                attemptID: .generated(),
                responseID: .generated(),
                route: .communicator,
                state: .accepted,
                occurredAt: Date()
            )
            await #expect(throws: WorldPersistenceError.missingCharacterDelivery) {
                try await persistence.characterDeliveries.record(outcome)
            }
        }
    }

    @Test("Duplicate event and source identities are idempotent")
    func duplicateEventsAreIdempotent() async throws {
        try await withPersistence { persistence in
            let sourceEventID = UUID().uuidString.lowercased()
            let first = try makeEvent(sourceEventID: sourceEventID)
            let receivedAt = Date(timeIntervalSince1970: 1_000)

            let inserted = try await persistence.events.append(first, receivedAt: receivedAt)
            let duplicateID = try await persistence.events.append(first, receivedAt: receivedAt)
            let duplicateSource = try await persistence.events.append(
                makeEvent(sourceID: first.source.id, sourceEventID: sourceEventID),
                receivedAt: receivedAt
            )

            let accepted = try #require(inserted.insertedEvent)
            #expect(accepted.worldSequence != nil)
            let duplicateByID = try #require(duplicateID.duplicateEvent)
            let duplicateBySource = try #require(duplicateSource.duplicateSourceEvent)
            #expect(duplicateByID.eventID == accepted.eventID)
            #expect(duplicateByID.worldSequence == accepted.worldSequence)
            #expect(duplicateBySource.eventID == accepted.eventID)
            #expect(duplicateBySource.worldSequence == accepted.worldSequence)

            #expect(try await !persistence.events.isProcessed(eventID: accepted.eventID))
            try await persistence.events.markProcessed(
                eventID: accepted.eventID,
                processedAt: Date()
            )
            #expect(try await persistence.events.isProcessed(eventID: accepted.eventID))
            let immutableEvent = try await persistence.database[MongoWorldCollection.events]
                .findOne(["_id": accepted.eventID.rawValue])
            #expect(immutableEvent?["processed_at"] == nil)
            #expect(
                try await persistence.database[MongoWorldCollection.eventProcessing]
                    .findOne(["_id": accepted.eventID.rawValue]) != nil
            )
        }
    }

    @Test("Typed person-utterance percepts survive MongoDB event persistence")
    func personUtterancePerceptEventRoundTrips() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let ingress = try makeIngress(
                suffix: suffix,
                conversationID: ConversationID(validating: "conversation:\(suffix)"),
                occurredAt: Date(timeIntervalSince1970: 3_000)
            )
            let percept = ingress.percept
            let event = try WorldEventEnvelope(
                occurredAt: percept.utterance.occurredAt,
                source: EventSource(
                    id: percept.utterance.sourceID,
                    kind: percept.utterance.source.rawValue,
                    sourceEventID: percept.utterance.utteranceID.rawValue
                ),
                subjectIDs: [percept.utterance.speakerID, percept.characterID],
                epistemic: EpistemicState(type: .reported, confidence: 1),
                payload: percept
            )

            let result = try await persistence.events.append(event, receivedAt: Date())
            let accepted = try #require(result.insertedEvent)
            let reloaded = try #require(
                try await persistence.events.event(withID: accepted.eventID)
            )

            #expect(reloaded.payload == event.payload)
            #expect(try reloaded.decodePayload(as: PersonUtterancePercept.self) == percept)
        }
    }

    @Test("Concurrent event appends receive unique increasing sequences")
    func concurrentSequencesAreUnique() async throws {
        try await withPersistence { persistence in
            let inserted = try await withThrowingTaskGroup(
                of: WorldEventEnvelope.self,
                returning: [WorldEventEnvelope].self
            ) { group in
                let receivedAt = Date(timeIntervalSince1970: 2_000)
                for _ in 0..<20 {
                    group.addTask {
                        let result = try await persistence.events.append(
                            makeEvent(),
                            receivedAt: receivedAt
                        )
                        return try #require(result.insertedEvent)
                    }
                }

                var events: [WorldEventEnvelope] = []
                for try await event in group {
                    events.append(event)
                }
                return events
            }

            let sequences = try inserted.map { try #require($0.worldSequence) }
            #expect(Set(sequences).count == inserted.count)
            #expect(sequences.allSatisfy { $0 > 0 })
        }
    }

    @Test("Current facts survive a database reconnect")
    func restartReadsCurrentFacts() async throws {
        let uri = try #require(mongoTestURI)
        let subjectID = try EntityID(validating: "person:\(UUID().uuidString.lowercased())")
        let current = try Fact(
            subjectID: subjectID,
            predicate: "location.current",
            value: .string("place:workshop"),
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: Date(),
            derivedFrom: [],
            producer: FactProducer(kind: "test", id: "mongo", version: "1")
        )

        let firstConnection = try await MongoWorldPersistence.connect(
            to: uri,
            logger: .init(label: "creature-world-mongodb-tests")
        )
        try await firstConnection.facts.save(current)
        await firstConnection.cluster.disconnect()

        let secondConnection = try await MongoWorldPersistence.connect(
            to: uri,
            logger: .init(label: "creature-world-mongodb-tests")
        )
        let reloaded = try await secondConnection.facts.currentFacts(subjectID: subjectID)
        await secondConnection.cluster.disconnect()

        let reloadedFact = try #require(reloaded.only)
        #expect(reloadedFact.factID == current.factID)
        #expect(reloadedFact.subjectID == current.subjectID)
        #expect(reloadedFact.predicate == current.predicate)
        #expect(reloadedFact.value == current.value)
    }

    @Test("Repeated fact saves replace one durable document")
    func repeatedFactSavesAreIdempotent() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let factID = try FactID(validating: "fact:\(suffix)")
            let subjectID = try EntityID(validating: "person:\(suffix)")
            let original = try Fact(
                factID: factID,
                subjectID: subjectID,
                predicate: "location.current",
                value: .object(["places": .array([])]),
                epistemic: EpistemicState(type: .observed, confidence: 1),
                validFrom: Date(),
                derivedFrom: [],
                producer: FactProducer(kind: "test", id: "mongo", version: "1")
            )
            var replacement = original
            replacement.value = .object([
                "places": .array([.string("place:stage")])
            ])

            try await persistence.facts.save(original)
            try await persistence.facts.save(replacement)

            let documents = try await persistence.database[MongoWorldCollection.facts]
                .find(["_id": factID.rawValue])
                .drain()
            let stored = try #require(
                try await persistence.facts.currentFacts(subjectID: subjectID).only
            )
            #expect(documents.count == 1)
            #expect(stored.factID == factID)
            #expect(stored.value == replacement.value)
        }
    }

    @Test("A newer fact about the same subject and predicate closes the older one")
    func newerFactSupersedesOlder() async throws {
        try await withPersistence { persistence in
            let subjectID = try EntityID(validating: "character:\(UUID().uuidString.lowercased())")
            let start = Date(timeIntervalSince1970: 1_789_600_000)
            func fact(_ region: String, at offset: TimeInterval) throws -> Fact {
                try Fact(
                    subjectID: subjectID,
                    predicate: "presence.region",
                    value: .string(region),
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    validFrom: start.addingTimeInterval(offset),
                    derivedFrom: [],
                    producer: FactProducer(kind: "test", id: "mongo", version: "1")
                )
            }
            let workshop = try fact("region:workshop", at: 0)
            let home = try fact("region:home", at: 60)
            let unrelated = try Fact(
                subjectID: subjectID, predicate: "presence.state", value: .string("awake"),
                epistemic: EpistemicState(type: .observed, confidence: 1), validFrom: start,
                derivedFrom: [], producer: FactProducer(kind: "test", id: "mongo", version: "1"))

            try await persistence.facts.save(workshop)
            try await persistence.facts.save(unrelated)
            try await persistence.facts.supersede(by: home)
            try await persistence.facts.save(home)
            // Saving the same fact again must not close it against itself.
            try await persistence.facts.supersede(by: home)
            try await persistence.facts.save(home)

            let current = try await persistence.facts.currentFacts(
                about: [subjectID], limit: WorldKnowledgeLimits.maximumFacts, at: start)
            #expect(current.map(\.factID) == [home.factID, unrelated.factID])
            let closed = try #require(
                try await persistence.database[MongoWorldCollection.facts]
                    .findOne(["_id": workshop.factID.rawValue]))
            #expect(closed["superseded_by"] as? String == home.factID.rawValue)
            #expect(closed["valid_to"] as? Date == home.validFrom)
        }
    }

    @Test("Facts for a percept are bounded and newest first across several subjects")
    func factsForAPerceptAreBounded() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let subjects = try (0..<3).map { try EntityID(validating: "entity:\(suffix)-\($0)") }
            let start = Date(timeIntervalSince1970: 1_789_600_000)
            for index in 0..<6 {
                try await persistence.facts.save(
                    Fact(
                        subjectID: subjects[index % 3],
                        predicate: "test.predicate-\(index)",
                        value: .number(Double(index)),
                        epistemic: EpistemicState(type: .observed, confidence: 1),
                        validFrom: start.addingTimeInterval(Double(index)),
                        derivedFrom: [],
                        producer: FactProducer(kind: "test", id: "mongo", version: "1")))
            }

            let facts = try await persistence.facts.currentFacts(
                about: Array(subjects[0...1]), limit: 3, at: start)

            // Subject 2's facts (indices 2, 5) are excluded; the newest three of the rest remain.
            #expect(facts.map(\.value) == [.number(4), .number(3), .number(1)])
            #expect(
                try await persistence.facts.currentFacts(about: [], limit: 3, at: start).isEmpty)
        }
    }

    @Test("A fact with a validity window is current until the window closes, then simply gone")
    func windowedFactsExpire() async throws {
        try await withPersistence { persistence in
            let room = try EntityID(validating: "region:\(UUID().uuidString.lowercased())")
            let start = Date(timeIntervalSince1970: 1_789_600_000)
            func lastScene(_ text: String, at offset: TimeInterval) throws -> Fact {
                try Fact(
                    subjectID: room, predicate: "scene.last", value: .string(text),
                    epistemic: EpistemicState(type: .observed, confidence: 1),
                    validFrom: start.addingTimeInterval(offset),
                    validTo: start.addingTimeInterval(offset + 3_600), derivedFrom: [],
                    producer: FactProducer(kind: "test", id: "mongo", version: "1"))
            }
            let towel = try lastScene("the towel", at: 0)
            try await persistence.facts.supersede(by: towel)
            try await persistence.facts.save(towel)

            // Within the hour it is what the room remembers; afterwards nothing is, and the
            // API's paged listing agrees with the percept query.
            let soon = start.addingTimeInterval(600)
            let later = start.addingTimeInterval(3_601)
            #expect(
                try await persistence.facts.currentFacts(about: [room], limit: 10, at: soon)
                    .map(\.factID) == [towel.factID])
            #expect(
                try await persistence.facts.currentFacts(
                    subjectID: room, after: nil, limit: 10, at: soon
                ).map(\.factID) == [towel.factID])
            #expect(
                try await persistence.facts.currentFacts(about: [room], limit: 10, at: later)
                    .isEmpty)

            // A newer scene replaces the older memory even though its window was still open.
            let pants = try lastScene("the purple pants", at: 60)
            try await persistence.facts.supersede(by: pants)
            try await persistence.facts.save(pants)
            #expect(
                try await persistence.facts.currentFacts(about: [room], limit: 10, at: soon)
                    .map(\.factID) == [pants.factID])
        }
    }

    @Test("Timer and source checkpoint repositories round trip")
    func timerAndCheckpointRoundTrip() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let sourceID = try SourceID(validating: "test:\(suffix)")
            let timer = WorldTimer(
                timerID: try TimerID(validating: "timer:\(suffix)"),
                purpose: try WorldEventType(validating: "test.timer-fired"),
                dueAt: Date().addingTimeInterval(60),
                subjectIDs: [],
                causedBy: [],
                payload: [
                    "context": .object(["reasons": .array([])])
                ]
            )
            let checkpoint = SourceCheckpoint(
                sourceID: sourceID,
                value: .object([
                    "cursor": .string("cursor-42"),
                    "pages": .array([]),
                ]),
                updatedAt: Date()
            )

            try await persistence.timers.save(timer)
            try await persistence.sourceCheckpoints.save(checkpoint)

            let reloadedTimer = try #require(
                try await persistence.timers.pending().first { $0.timerID == timer.timerID }
            )
            let reloadedCheckpoint = try #require(
                try await persistence.sourceCheckpoints.checkpoint(for: sourceID)
            )
            #expect(reloadedTimer.purpose == timer.purpose)
            #expect(reloadedTimer.status == .pending)
            #expect(reloadedTimer.payload == timer.payload)
            #expect(reloadedCheckpoint.sourceID == checkpoint.sourceID)
            #expect(reloadedCheckpoint.value == checkpoint.value)
        }
    }

    @Test("Timer claims, completion, replacement, and cancellation are conditional")
    func timerLifecycleIsAtomic() async throws {
        try await withPersistence { persistence in
            let suffix = UUID().uuidString.lowercased()
            let timerID = try TimerID.stable("test:\(suffix):purpose")
            let firstDueAt = Date(timeIntervalSince1970: 10_000)
            let first = WorldTimer(
                timerID: timerID,
                purpose: try WorldEventType(validating: "test.timer-fired"),
                dueAt: firstDueAt,
                subjectIDs: [],
                causedBy: [],
                payload: [:]
            )
            try await persistence.timers.schedule(first)

            let claimed = try #require(
                try await persistence.timers.claim(
                    timerID: timerID,
                    dueAt: firstDueAt,
                    firingAt: firstDueAt
                )
            )
            #expect(claimed.status == .firing)
            #expect(
                try await persistence.timers.markFired(
                    timerID: timerID,
                    dueAt: firstDueAt,
                    firedAt: firstDueAt
                )
            )
            #expect(
                try await persistence.timers.claim(
                    timerID: timerID,
                    dueAt: firstDueAt,
                    firingAt: firstDueAt
                ) == nil
            )

            let replacementDueAt = firstDueAt.addingTimeInterval(60)
            let replacement = WorldTimer(
                timerID: timerID,
                purpose: first.purpose,
                dueAt: replacementDueAt,
                subjectIDs: [],
                causedBy: [],
                payload: [:]
            )
            try await persistence.timers.schedule(replacement)
            #expect(
                try await persistence.timers.claim(
                    timerID: timerID,
                    dueAt: firstDueAt,
                    firingAt: replacementDueAt
                ) == nil
            )
            #expect(
                try await persistence.timers.cancel(
                    timerID: timerID,
                    canceledAt: replacementDueAt
                )
            )
            #expect(
                try await !persistence.timers.cancel(
                    timerID: timerID,
                    canceledAt: replacementDueAt
                )
            )
            #expect(
                try await !persistence.timers.recoverable(limit: 100).contains {
                    $0.timerID == timerID
                }
            )
        }
    }

    private func withPersistence<T: Sendable>(
        _ operation: @Sendable (MongoWorldPersistence) async throws -> T
    ) async throws -> T {
        let persistence = try await MongoWorldPersistence.connect(
            to: try #require(mongoTestURI),
            logger: .init(label: "creature-world-mongodb-tests")
        )
        do {
            let result = try await operation(persistence)
            await persistence.cluster.disconnect()
            return result
        } catch {
            await persistence.cluster.disconnect()
            throw error
        }
    }

    private func makeEvent(sourceID: SourceID? = nil, sourceEventID: String? = nil) throws
        -> WorldEventEnvelope
    {
        let resolvedSourceID =
            try sourceID
            ?? SourceID(validating: "test:\(UUID().uuidString.lowercased())")
        return try WorldEventEnvelope(
            type: WorldEventType(validating: "test.observed"),
            occurredAt: Date(),
            source: EventSource(
                id: resolvedSourceID,
                kind: "test",
                sourceEventID: sourceEventID
            ),
            subjectIDs: [],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
    }

    private func makeDelivery(
        suffix: String,
        conversationID: ConversationID,
        inResponseTo utteranceID: UtteranceID,
        createdAt: Date
    ) throws -> StoredCharacterDelivery {
        let intent = try CharacterUtteranceIntent(
            responseID: ResponseID(validating: "response:\(suffix)"),
            conversationID: conversationID,
            characterID: EntityID(validating: "character:beaky"),
            recipientID: EntityID(validating: "person:april"),
            inResponseToUtteranceID: utteranceID,
            text: "Beaky answer \(suffix)",
            urgency: 0.5,
            createdAt: createdAt
        )
        let presence = try PersonPresence(
            personID: intent.recipientID,
            state: .unknown,
            confidence: 0,
            observedAt: createdAt,
            validUntil: createdAt,
            physicallyAudible: false
        )
        let decision = try CharacterDeliveryDecision(
            attemptID: DeliveryAttemptID(validating: "delivery-attempt:\(suffix)"),
            responseID: intent.responseID,
            route: .communicator,
            privacyMode: .private,
            reason: .presenceUncertain,
            decidedAt: createdAt,
            presence: presence
        )
        let item = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:\(suffix)"),
            conversationID: conversationID,
            authorID: intent.characterID,
            authorKind: .character,
            text: intent.text,
            createdAt: createdAt,
            responseID: intent.responseID
        )
        return StoredCharacterDelivery(intent: intent, decision: decision, conversationItem: item)
    }

    private func makeIngress(
        suffix: String,
        conversationID: ConversationID,
        occurredAt: Date
    ) throws -> StoredUtteranceIngress {
        let utterance = try PersonUtterance(
            utteranceID: UtteranceID(validating: "utterance:\(suffix)"),
            conversationID: conversationID,
            speakerID: EntityID(validating: "person:april"),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: "Message \(suffix)",
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: occurredAt,
            confidence: 1
        )
        let item = try ConversationItem(
            itemID: ConversationItemID(validating: "conversation-item:\(suffix)"),
            conversationID: conversationID,
            authorID: utterance.speakerID,
            authorKind: .person,
            text: utterance.text,
            createdAt: occurredAt,
            utteranceID: utterance.utteranceID
        )
        return StoredUtteranceIngress(
            percept: try PersonUtterancePercept(
                characterID: utterance.addresseeIDs[0],
                utterance: utterance,
                priorConversationItems: []
            ),
            conversationItem: item
        )
    }
}

extension EventAppendResult {
    fileprivate var insertedEvent: WorldEventEnvelope? {
        guard case .inserted(let event) = self else { return nil }
        return event
    }

    fileprivate var duplicateEvent: WorldEventEnvelope? {
        guard case .duplicateEvent(let event) = self else { return nil }
        return event
    }

    fileprivate var duplicateSourceEvent: WorldEventEnvelope? {
        guard case .duplicateSourceEvent(let event) = self else { return nil }
        return event
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

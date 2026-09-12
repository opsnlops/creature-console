import CreatureAppSupport
import Foundation
import Testing
import WorldCore

@testable import World_Viewer

@MainActor
@Suite("World Viewer store")
struct WorldStoreTests {
    private let conversationID = try! ConversationID(validating: "conversation:april-beaky")
    private let april = try! EntityID(validating: "person:april")
    private let beaky = try! EntityID(validating: "character:beaky")

    @Test("A snapshot seeds facts and timers and the timeline is bounded to the newest events")
    func snapshotSeedsAndBounds() async throws {
        let total = WorldStore.maximumEvents + 50
        let history = try (1...total).map { try makeEvent(sequence: Int64($0)) }
        let fact = try makeFact()
        let world = ScriptedWorld(history: history)
        await world.script([
            .snapshot(
                WorldSnapshot(
                    latestSequence: Int64(total), facts: [fact], timers: [],
                    factsTruncated: false, timersTruncated: false)),
            .hold,
        ])
        let store = makeStore(world)

        store.start()
        defer { store.stop() }
        try await settle { store.streamState == .live && !store.events.isEmpty }

        #expect(store.facts == [fact])
        #expect(store.events.count == WorldStore.maximumEvents)
        #expect(store.events.first?.worldSequence == 51)
        #expect(store.events.last?.worldSequence == Int64(total))
        #expect(store.latestSequence == Int64(total))
        #expect(store.health?.buildVersion == "0.3.0")
    }

    @Test("A dropped stream resumes after the last sequence seen, without gaps or repeats")
    func resumesWithoutGap() async throws {
        let world = ScriptedWorld(history: [])
        let first = try makeEvent(sequence: 1)
        let second = try makeEvent(sequence: 2)
        let third = try makeEvent(sequence: 3)
        await world.script([
            .snapshot(
                WorldSnapshot(
                    latestSequence: 0, facts: [], timers: [], factsTruncated: false,
                    timersTruncated: false)),
            .event(first), .event(second), .end,
        ])
        await world.script([.event(second), .event(third), .hold])
        let store = makeStore(world)

        store.start()
        defer { store.stop() }
        try await settle { store.events.count == 3 }

        #expect(store.events.map(\.worldSequence) == [1, 2, 3])
        #expect(await world.resumePoints == [nil, 2])
        #expect(store.streamState == .live)
    }

    @Test("A resnapshot_required frame reconnects without a resume point")
    func resnapshotsWhenAsked() async throws {
        let world = ScriptedWorld(history: [])
        await world.script([
            .snapshot(
                WorldSnapshot(
                    latestSequence: 0, facts: [], timers: [], factsTruncated: false,
                    timersTruncated: false)),
            .event(try makeEvent(sequence: 1)), .end,
        ])
        await world.script([.resnapshotRequired, .end])
        await world.script([
            .snapshot(
                WorldSnapshot(
                    latestSequence: 1, facts: [], timers: [], factsTruncated: false,
                    timersTruncated: false)),
            .hold,
        ])
        let store = makeStore(world)

        store.start()
        defer { store.stop() }
        try await settle { await world.resumePoints.count == 3 && store.streamState == .live }

        #expect(await world.resumePoints == [nil, 1, nil])
    }

    @Test("Beaky's turns are joined to the router's delivery record by response ID")
    func joinsDeliveries() async throws {
        let world = ScriptedWorld(history: [])
        await world.script([.hold])
        let question = try ConversationItem(
            conversationID: conversationID, authorID: april, authorKind: .person,
            text: "Are you there?", createdAt: Date(timeIntervalSince1970: 1_789_200_000),
            utteranceID: .generated())
        let responseID = ResponseID.generated()
        let answer = try ConversationItem(
            conversationID: conversationID, authorID: beaky, authorKind: .character,
            text: "Always.", createdAt: Date(timeIntervalSince1970: 1_789_200_001),
            responseID: responseID)
        let delivery = try makeDelivery(for: answer, responseID: responseID)
        await world.setConversation(items: [question, answer], deliveries: [delivery])
        let store = makeStore(world)

        store.start()
        defer { store.stop() }
        try await settle { store.conversationItems.count == 2 }

        #expect(store.deliveries[responseID] == delivery)
        #expect(store.deliveries.count == 1)
        #expect(store.conversationItems == [question, answer])
    }

    // MARK: - Helpers

    private func makeStore(_ world: ScriptedWorld) -> WorldStore {
        let defaults = UserDefaults(suiteName: "WorldStoreTests.\(UUID().uuidString)")!
        let connection = WorldViewerConnection(defaults: defaults, keyStore: nil)
        return WorldStore(connection: connection, reconnectDelay: .zero) {
            ScriptedScryer(world: world)
        }
    }

    private func settle(
        timeout: Duration = .seconds(5), until condition: @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !(await condition()) {
            guard clock.now < deadline else {
                Issue.record("The store did not settle within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeEvent(sequence: Int64) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "test.observed"),
            occurredAt: Date(timeIntervalSince1970: 1_789_200_000 + Double(sequence)),
            receivedAt: Date(timeIntervalSince1970: 1_789_200_000.25 + Double(sequence)),
            worldSequence: sequence,
            source: EventSource(id: SourceID(validating: "test:viewer"), kind: "test"),
            subjectIDs: [april],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: ["sequence": .number(Double(sequence))]
        )
    }

    private func makeFact() throws -> Fact {
        try Fact(
            factID: .generated(), subjectID: april, predicate: "presence.state",
            value: .string("unknown"),
            epistemic: EpistemicState(type: .inferred, confidence: 0.5),
            validFrom: Date(timeIntervalSince1970: 1_789_200_000), derivedFrom: [],
            producer: FactProducer(kind: "reducer", id: "presence", version: "1"))
    }

    private func makeDelivery(for item: ConversationItem, responseID: ResponseID) throws
        -> CharacterDeliveryRecord
    {
        let intent = try CharacterUtteranceIntent(
            responseID: responseID, conversationID: conversationID, characterID: beaky,
            recipientID: april, text: item.text, urgency: 0.5, createdAt: item.createdAt)
        let presence = try PersonPresence(
            personID: april, state: .unknown, confidence: 0, observedAt: item.createdAt,
            validUntil: item.createdAt, physicallyAudible: false)
        let decision = try CharacterDeliveryDecision(
            responseID: responseID, route: .communicator, privacyMode: .private,
            reason: .presenceUncertain, decidedAt: item.createdAt, presence: presence)
        return CharacterDeliveryRecord(
            intent: intent, decision: decision, outcome: nil, conversationItem: item)
    }
}

/// One scripted connection to the world stream: frames in order, then either the stream ends
/// (as it does after `resnapshot_required` or a World restart) or stays open.
enum ScriptedFrame {
    case snapshot(WorldSnapshot)
    case event(WorldEventEnvelope)
    case resnapshotRequired
    case end
    case hold
}

actor ScriptedWorld {
    let history: [WorldEventEnvelope]
    private var connections: [[ScriptedFrame]] = []
    private(set) var resumePoints: [Int64?] = []
    private var items: [ConversationItem] = []
    private var deliveries: [CharacterDeliveryRecord] = []

    init(history: [WorldEventEnvelope]) {
        self.history = history
    }

    func script(_ frames: [ScriptedFrame]) {
        connections.append(frames)
    }

    func setConversation(items: [ConversationItem], deliveries: [CharacterDeliveryRecord]) {
        self.items = items
        self.deliveries = deliveries
    }

    func conversation() -> ([ConversationItem], [CharacterDeliveryRecord]) {
        (items, deliveries)
    }

    func nextConnection(resumingAfter sequence: Int64?) -> [ScriptedFrame] {
        resumePoints.append(sequence)
        guard !connections.isEmpty else { return [.hold] }
        return connections.removeFirst()
    }

    func page(after sequence: Int64, limit: Int) -> WorldEventPage {
        let remaining = history.filter { ($0.worldSequence ?? 0) > sequence }
        let events = Array(remaining.prefix(limit))
        return WorldEventPage(
            events: events, nextSequence: events.last?.worldSequence ?? sequence,
            hasMore: remaining.count > events.count)
    }
}

struct ScriptedScryer: WorldScrying {
    let world: ScriptedWorld

    func health() async throws -> WorldHealth {
        WorldHealth(
            status: "ok", service: "creature-world", buildVersion: "0.3.0", mongodb: "ok",
            schemaVersion: 1)
    }

    func events(after sequence: Int64, limit: Int) async throws -> WorldEventPage {
        await world.page(after: sequence, limit: limit)
    }

    func facts(limit: Int) async throws -> WorldFactPage {
        WorldFactPage(facts: [], nextFactID: nil, hasMore: false)
    }

    func timers(limit: Int) async throws -> WorldTimerPage {
        WorldTimerPage(timers: [], nextTimerID: nil, hasMore: false)
    }

    func conversationItems(in conversationID: ConversationID, limit: Int) async throws
        -> ConversationItemPage
    {
        ConversationItemPage(items: await world.conversation().0, nextItemID: nil, hasMore: false)
    }

    func deliveries(in conversationID: ConversationID, limit: Int) async throws
        -> CharacterDeliveryPage
    {
        CharacterDeliveryPage(
            deliveries: await world.conversation().1, nextResponseID: nil, hasMore: false)
    }

    func characters() async throws -> CharacterSessionPage {
        CharacterSessionPage(sessions: [])
    }

    func scenes(limit: Int) async throws -> ScenePage {
        ScenePage(scenes: [])
    }

    func worldFrames(resumeAfter sequence: Int64?) throws -> WorldStreamFrames {
        let world = world
        return WorldStreamFrames { continuation in
            let task = Task {
                for frame in await world.nextConnection(resumingAfter: sequence) {
                    switch frame {
                    case .snapshot(let snapshot): continuation.yield(.snapshot(snapshot))
                    case .event(let event): continuation.yield(.event(event))
                    case .resnapshotRequired: continuation.yield(.resnapshotRequired)
                    case .end: continuation.finish()
                    case .hold: return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func conversationUpdates(in conversationID: ConversationID) throws
        -> WorldConversationUpdateStream
    {
        WorldConversationUpdateStream { _ in }
    }
}

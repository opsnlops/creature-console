import Foundation
import Testing
import WorldCore

@Suite("Scenes: the world gives the floor")
struct SceneServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_789_400_000)
    private let home = try! EntityID(validating: "region:home")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let april = try! EntityID(validating: "person:april")
    private let conversation = try! ConversationID(validating: "conversation:april-house")

    @Test("Opening offers the floor to the addressee first and schedules its deadline")
    func openingOffersTheFloor() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: mango), participants: [beaky, mango])

        #expect(scene.participants == [mango, beaky])
        #expect(scene.floor?.characterID == mango)
        #expect(scene.floor?.deadline == Self.now.addingTimeInterval(8))
        let offers = await world.announced.offers
        #expect(offers.map(\.characterID) == [mango])
        #expect(offers.first?.responseID == scene.floor?.responseID)
        #expect(await world.timers.scheduled.map(\.purpose) == [SceneService.floorExpiredEventType])
        #expect(await world.announced.types.first == SceneService.openedEventType)
    }

    @Test(
        "Turns move the floor around the room; the scene closes and is performed once everyone passes"
    )
    func turnsRotateAndEveryonePassedCloses() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])

        let first = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: try #require(scene.floor?.responseID),
                text: "April, I think the servors are here!"),
            to: scene.sceneID)
        #expect(first.disposition == .accepted)
        #expect(first.scene.floor?.characterID == mango)

        let second = try await world.service.submit(
            SceneTurnSubmission(
                characterID: mango, responseID: try #require(first.scene.floor?.responseID),
                text: "Or it is more heat sinks. It is always heat sinks."),
            to: scene.sceneID)
        #expect(second.scene.floor?.characterID == beaky)

        let beakyPasses = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: try #require(second.scene.floor?.responseID),
                text: nil),
            to: scene.sceneID)
        #expect(beakyPasses.scene.state == .open)
        let mangoPasses = try await world.service.submit(
            SceneTurnSubmission(
                characterID: mango, responseID: try #require(beakyPasses.scene.floor?.responseID),
                text: nil),
            to: scene.sceneID)

        let final = try #require(try await world.service.scene(id: scene.sceneID))
        #expect(mangoPasses.disposition == .accepted)
        #expect(final.state == .performed)
        #expect(final.closeReason == .everyonePassed)
        #expect(final.spokenTurns.map(\.characterID) == [beaky, mango])
        #expect(final.turns.count == 4)
        #expect(final.performance?.providerReference == "animation:scene")
        #expect(await world.performer.performed.map(\.sceneID) == [scene.sceneID])
        #expect(await world.recorded.count == 2)
        #expect(
            await world.announced.types.last(2) == [
                SceneService.closedEventType, SceneService.performedEventType,
            ])
    }

    @Test("Only the floor holder may speak, and the same response is not recorded twice")
    func floorIsGuarded() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let responseID = try #require(scene.floor?.responseID)

        let jumpIn = try await world.service.submit(
            SceneTurnSubmission(characterID: mango, responseID: responseID, text: "Me first"),
            to: scene.sceneID)
        #expect(jumpIn.disposition == .notYourTurn)

        let turn = try await world.service.submit(
            SceneTurnSubmission(characterID: beaky, responseID: responseID, text: "Hello!"),
            to: scene.sceneID)
        let again = try await world.service.submit(
            SceneTurnSubmission(characterID: beaky, responseID: responseID, text: "Hello!"),
            to: scene.sceneID)
        #expect(turn.disposition == .accepted)
        #expect(again.disposition == .duplicate)
        #expect(again.scene.turns.count == 1)
    }

    @Test("A floor nobody answers by the deadline counts as a pass")
    func deadlineIsAPass() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let offered = try #require(scene.floor?.responseID)

        try await world.service.floorExpired(sceneID: scene.sceneID, responseID: offered)
        // A late answer to an expired floor is not this character's turn any more.
        let late = try await world.service.submit(
            SceneTurnSubmission(characterID: beaky, responseID: offered, text: "Wait!"),
            to: scene.sceneID)

        let current = try #require(try await world.service.scene(id: scene.sceneID))
        #expect(late.disposition == .notYourTurn)
        #expect(current.turns.first?.isPass == true)
        #expect(current.floor?.characterID == mango)
    }

    @Test("The cutoffs end a scene that would otherwise run on")
    func cutoffsClose() async throws {
        let world = makeWorld(limits: SceneLimits(maximumTurns: 3))
        var scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        for line in ["One.", "Two.", "Three."] {
            let floor = try #require(scene.floor)
            scene = try await world.service.submit(
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID, text: line),
                to: scene.sceneID
            ).scene
        }
        let final = try #require(try await world.service.scene(id: scene.sceneID))
        #expect(final.closeReason == .maximumTurns)
        #expect(final.state == .performed)

        let talky = makeWorld(limits: SceneLimits(maximumSpokenSeconds: 4, wordsPerSecond: 1))
        var long = try await talky.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let floor = try #require(long.floor)
        long = try await talky.service.submit(
            SceneTurnSubmission(
                characterID: floor.characterID, responseID: floor.responseID,
                text: "one two three four five words"),
            to: long.sceneID
        ).scene
        #expect(long.closeReason == .maximumSpokenSeconds)
    }

    @Test(
        "A scene where nobody speaks is abandoned, not performed; a failed performance is recorded")
    func abandonedAndFailed() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        for _ in 0..<2 {
            let current = try #require(try await world.service.scene(id: scene.sceneID))
            let floor = try #require(current.floor)
            _ = try await world.service.submit(
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID, text: nil),
                to: scene.sceneID)
        }
        let quiet = try #require(try await world.service.scene(id: scene.sceneID))
        #expect(quiet.state == .abandoned)
        #expect(await world.performer.performed.isEmpty)

        let broken = makeWorld(performerFails: true)
        let loud = try await broken.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky])
        let floor = try #require(loud.floor)
        _ = try await broken.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: floor.responseID, text: "Alone but talking."),
            to: loud.sceneID)
        _ = try await broken.service.submit(
            SceneTurnSubmission(
                characterID: beaky,
                responseID: try #require(
                    try await broken.service.scene(id: loud.sceneID)?.floor?.responseID),
                text: nil),
            to: loud.sceneID)
        let failed = try #require(try await broken.service.scene(id: loud.sceneID))
        #expect(failed.state == .abandoned)
        #expect(failed.performance?.state == .failed)
        #expect(failed.performance?.errorCode == "scene_performance_failed")
    }

    @Test("A new scene in the region interrupts an open one")
    func newSceneInterrupts() async throws {
        let world = makeWorld()
        let first = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let second = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: mango), participants: [beaky, mango])

        let interrupted = try #require(try await world.service.scene(id: first.sceneID))
        #expect(interrupted.state == .abandoned)
        #expect(interrupted.closeReason == .interrupted)
        #expect(second.state == .open)
    }

    // MARK: - Helpers

    private struct TestWorld {
        let service: SceneService
        let announced: AnnouncedEvents
        let timers: ScheduledTimers
        let recorded: RecordedTurns
        let performer: FakePerformer
    }

    private func makeWorld(limits: SceneLimits = SceneLimits(), performerFails: Bool = false)
        -> TestWorld
    {
        let announced = AnnouncedEvents()
        let timers = ScheduledTimers()
        let recorded = RecordedTurns()
        let performer = FakePerformer(fails: performerFails)
        let service = SceneService(
            repository: InMemoryScenes(),
            clock: ManualWorldClock(now: Self.now),
            limits: limits,
            performer: performer,
            announce: { await announced.record($0) },
            scheduleDeadline: { await timers.schedule($0) },
            recordTurn: { _, turn in
                await recorded.record(turn)
                return .generated()
            }
        )
        return TestWorld(
            service: service, announced: announced, timers: timers, recorded: recorded,
            performer: performer)
    }

    private func makeTrigger(addressee: EntityID) -> SceneTrigger {
        SceneTrigger(
            kind: .personUtterance,
            eventID: .generated(),
            utteranceID: .generated(),
            speakerID: april,
            addresseeID: addressee,
            text: "What do you think is in the box?"
        )
    }
}

private actor InMemoryScenes: SceneRepository {
    private var scenes: [SceneID: Scene] = [:]

    func scene(id: SceneID) -> Scene? { scenes[id] }
    func save(_ scene: Scene) { scenes[scene.sceneID] = scene }
    func openScenes(in regionID: EntityID) -> [Scene] {
        scenes.values.filter { $0.regionID == regionID && $0.state == .open }
            .sorted { $0.openedAt < $1.openedAt }
    }
    func recentScenes(limit: Int) -> [Scene] {
        Array(scenes.values.sorted { $0.openedAt > $1.openedAt }.prefix(limit))
    }
}

private actor AnnouncedEvents {
    private(set) var events: [WorldEventEnvelope] = []
    func record(_ event: WorldEventEnvelope) { events.append(event) }
    var types: [WorldEventType] { events.map(\.type) }
    var offers: [SceneTurnOffer] {
        events.filter { $0.type == SceneTurnOffer.eventType }.compactMap { event in
            let data = try? WorldJSON.makeEncoder().encode(WorldJSONValue.object(event.payload))
            return data.flatMap {
                try? WorldJSON.makeDecoder().decode(SceneTurnOffer.self, from: $0)
            }
        }
    }
}

private actor ScheduledTimers {
    private(set) var scheduled: [WorldTimer] = []
    func schedule(_ timer: WorldTimer) { scheduled.append(timer) }
}

private actor RecordedTurns {
    private(set) var turns: [SceneTurn] = []
    var count: Int { turns.count }
    func record(_ turn: SceneTurn) { turns.append(turn) }
}

private actor FakePerformer: ScenePerforming {
    private(set) var performed: [Scene] = []
    private let fails: Bool

    init(fails: Bool) { self.fails = fails }

    func perform(_ scene: Scene) async throws -> ScenePerformance {
        if fails { throw WorldContractError.invalidScene }
        performed.append(scene)
        return ScenePerformance(
            state: .performed, providerReference: "animation:scene", occurredAt: scene.openedAt)
    }
}

extension Array {
    fileprivate func last(_ n: Int) -> [Element] { Array(suffix(n)) }
}

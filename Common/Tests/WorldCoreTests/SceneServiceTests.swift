import Foundation
import Testing
import WorldCore

@Suite("Scenes: the world gives the floor")
struct SceneServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_789_400_000)
    private let home = try! EntityID(validating: "region:home")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let kenny = try! EntityID(validating: "character:kenny")
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
                text: "Or is it more heat sinks, Beaky?"),
            to: scene.sceneID)
        // A question keeps the scene open past the first round.
        #expect(second.scene.state == .open)
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
        // The performer heard the scene open and each spoken turn as it landed, so a streaming
        // stage can play them before the scene closes.
        #expect(await world.performer.opened == [scene.sceneID])
        #expect(await world.performer.spoken.map(\.characterID) == [beaky, mango])
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

    @Test("A line may arrive sentence by sentence: spoken as it lands, joined when it is done")
    func streamedTurn() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let responseID = try #require(scene.floor?.responseID)
        let firstDeadline = try #require(scene.floor?.deadline)

        try await world.clock.advance(by: 3)
        let first = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: responseID, text: "Not quite, Kenny.", piece: 0),
            to: scene.sceneID)
        #expect(first.disposition == .accepted)
        #expect(first.scene.floor?.pieces == ["Not quite, Kenny."])
        // The deadline moved out with the sentence, so the rest may follow.
        #expect(try #require(first.scene.floor?.deadline) > firstDeadline)
        // The room heard it already.
        #expect(await world.performer.pieces.map(\.1) == ["Not quite, Kenny."])
        // A retry of the same piece is a duplicate; skipping ahead is not this turn.
        #expect(
            try await world.service.submit(
                SceneTurnSubmission(
                    characterID: beaky, responseID: responseID, text: "Not quite, Kenny.", piece: 0),
                to: scene.sceneID
            ).disposition == .duplicate)
        #expect(
            try await world.service.submit(
                SceneTurnSubmission(
                    characterID: beaky, responseID: responseID, text: "?", piece: 5),
                to: scene.sceneID
            ).disposition == .notYourTurn)
        // An early timer from the first deadline changes nothing.
        try await world.service.floorExpired(sceneID: scene.sceneID, responseID: responseID)
        #expect(try await world.service.scene(id: scene.sceneID)?.floor?.responseID == responseID)

        _ = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: responseID, text: "The door was unlocked,",
                piece: 1),
            to: scene.sceneID)
        // "That was the whole line": the pieces become the turn, recorded once, and the
        // performer is told it was streamed so it does not say it twice.
        let done = try await world.service.submit(
            SceneTurnSubmission(characterID: beaky, responseID: responseID, text: nil),
            to: scene.sceneID)
        #expect(done.disposition == .accepted)
        let turn = try #require(done.scene.turns.first)
        #expect(turn.text == "Not quite, Kenny. The door was unlocked,")
        #expect(turn.isPass == false)
        #expect(
            await world.recorded.turns.map(\.text) == ["Not quite, Kenny. The door was unlocked,"])
        #expect(await world.performer.streamedTurns.count == 1)
        #expect(await world.performer.spoken.isEmpty)
        #expect(done.scene.floor?.characterID == mango)
        let types = await world.announced.events.map(\.type)
        #expect(types.filter { $0 == SceneService.turnPieceEventType }.count == 2)
        #expect(types.contains(SceneService.turnEventType))
    }

    @Test("The next floor waits until the room has nearly finished the last line")
    func floorIsPacedToPlayback() async throws {
        // Ten characters a second and no per-sentence cost: an eighty-character line is
        // eight seconds of speech; the floor is offered one second before it ends.
        let world = makeWorld(
            limits: SceneLimits(
                charactersPerSecond: 10, sentenceSeconds: 0, turnLeadSeconds: 1))
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let responseID = try #require(scene.floor?.responseID)
        let twentyWords = String(repeating: "word ", count: 16).dropLast() + "."
        #expect(twentyWords.count == 80)

        let taken = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: responseID, text: String(twentyWords)),
            to: scene.sceneID)

        // Nobody has the floor yet; Mango is next, once the room catches up. Beaky's floor
        // deadline is withdrawn: an answered floor never expires.
        #expect(taken.scene.floor == nil)
        #expect(await world.timers.canceled.contains(SceneService.floorTimerID(for: responseID)))
        #expect(taken.scene.pendingFloor == mango)
        let spokenUntil = try #require(taken.scene.spokenUntil)
        #expect(abs(spokenUntil.timeIntervalSince(Self.now) - 8) < 0.01)
        let ready = try #require(
            await world.timers.scheduled.last { $0.purpose == SceneService.floorReadyEventType })
        #expect(abs(ready.dueAt.timeIntervalSince(Self.now) - 7) < 0.01)
        #expect(ready.payload["character_id"] == .string(mango.rawValue))
        // Only one turn offered so far.
        #expect(await world.announced.offers.count == 1)

        // The room is about to finish: the floor goes to Mango, with a fresh deadline.
        try await world.clock.advance(by: 7)
        try await world.service.floorReady(sceneID: scene.sceneID)
        let current = try #require(try await world.service.scene(id: scene.sceneID))
        #expect(current.floor?.characterID == mango)
        #expect(current.pendingFloor == nil)
        #expect(await world.announced.offers.count == 2)
        // A second ready for the same scene changes nothing.
        try await world.service.floorReady(sceneID: scene.sceneID)
        #expect(await world.announced.offers.count == 2)

        // Mango's short line (eleven characters, 1.1 s) queues behind whatever is still
        // playing (one second left).
        let mangoFloor = try #require(current.floor?.responseID)
        let quick = try await world.service.submit(
            SceneTurnSubmission(characterID: mango, responseID: mangoFloor, text: "Heat sinks."),
            to: scene.sceneID)
        let queued = try #require(quick.scene.spokenUntil)
        #expect(abs(queued.timeIntervalSince(spokenUntil) - 1.1) < 0.01)
    }

    @Test("A streamed line that goes quiet is the line so far when the floor expires")
    func streamedLineExpires() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let responseID = try #require(scene.floor?.responseID)
        _ = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: responseID, text: "Servos, I hope!", piece: 0),
            to: scene.sceneID)
        try await world.clock.advance(by: SceneLimits().floorSeconds + 1)

        try await world.service.floorExpired(sceneID: scene.sceneID, responseID: responseID)

        let current = try #require(try await world.service.scene(id: scene.sceneID))
        #expect(current.turns.first?.text == "Servos, I hope!")
        #expect(current.floor?.characterID == mango)
    }

    @Test("A floor nobody answers by the deadline counts as a pass")
    func deadlineIsAPass() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let offered = try #require(scene.floor?.responseID)

        // The timer fires early by mistake: the floor is still open, nothing happens.
        try await world.service.floorExpired(sceneID: scene.sceneID, responseID: offered)
        #expect(try await world.service.scene(id: scene.sceneID)?.floor?.responseID == offered)
        try await world.clock.advance(by: SceneLimits().floorSeconds)
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

    @Test(
        "One round by default: the scene closes once everyone has spoken and nothing asks for more")
    func roundDoneCloses() async throws {
        let kenny = try EntityID(validating: "character:kenny")
        let world = makeWorld()
        var scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango, kenny])
        for line in [
            "I love you too, April.", "Noted, and recorded in MongoDB.",
            "Kenny loves you too, with all his pieces.",
        ] {
            let floor = try #require(scene.floor)
            scene = try await world.service.submit(
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID, text: line),
                to: scene.sceneID
            ).scene
        }
        let final = try #require(try await world.service.scene(id: scene.sceneID))
        // Kenny naming himself is not a call on anyone.
        #expect(final.closeReason == .roundDone)
        #expect(final.turns.count == 3)
        #expect(final.state == .performed)

        // A name or a question at the end of the round keeps it going.
        let asked = makeWorld()
        var open = try await asked.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        for line in ["Mango will know.", "I do know."] {
            let floor = try #require(open.floor)
            open = try await asked.service.submit(
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID, text: line),
                to: open.sceneID
            ).scene
        }
        #expect(open.closeReason == .roundDone)
        var named = try await asked.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        for line in ["Mango will know.", "I do, Beaky."] {
            let floor = try #require(named.floor)
            named = try await asked.service.submit(
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID, text: line),
                to: named.sceneID
            ).scene
        }
        #expect(named.state == .open)
        #expect(named.turns.count == 2)
    }

    @Test("The cutoffs end a scene that would otherwise run on")
    func cutoffsClose() async throws {
        let world = makeWorld(limits: SceneLimits(maximumTurns: 3))
        var scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        for line in ["One?", "Two?", "Three?"] {
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

        let talky = makeWorld(
            limits: SceneLimits(maximumSpokenSeconds: 4, charactersPerSecond: 5))
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
        // Alone, her one line is the round; the scene closes and the performance fails.
        _ = try await broken.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: floor.responseID, text: "Alone but talking."),
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
        let clock: ManualWorldClock
    }

    @Test("A scene the house opened is short, and the room hears the event if the lead is silent")
    func houseScenesAreShortAndNeverSilent() async throws {
        let world = makeWorld(limits: SceneLimits(houseMaximumTurns: 2, turnLeadSeconds: 3_600))
        let trigger = SceneTrigger(
            kind: .worldEvent, eventID: .generated(),
            text: "A person was just seen at the carport.")
        var scene = try await world.service.open(
            regionID: home, conversationID: conversation, trigger: trigger,
            participants: [beaky, mango, kenny])

        // Beaky's mind fails: the room still hears the plain event, as her line.
        let beakyFloor = try #require(scene.floor)
        scene = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: beakyFloor.responseID, text: nil),
            to: scene.sceneID
        ).scene
        #expect(scene.turns.first?.text == "A person was just seen at the carport.")
        let turn = try #require(
            await world.announced.events.last { $0.type == SceneService.turnEventType })
        #expect(turn.payload["fallback"] == .bool(true))
        #expect(turn.payload["pass"] == .bool(false))

        // Mango's reaction is the second and last turn; Kenny never gets the floor.
        let mangoFloor = try #require(scene.floor)
        #expect(mangoFloor.characterID == mango)
        scene = try await world.service.submit(
            SceneTurnSubmission(
                characterID: mango, responseID: mangoFloor.responseID, text: "Probably Jesse."),
            to: scene.sceneID
        ).scene
        #expect(scene.closeReason == .maximumTurns)
        #expect(scene.turns.count == 2)

        // April's scenes keep the long cap, as long as the lines keep asking.
        let chatty = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        var floor = try #require(chatty.floor)
        var current = chatty
        for _ in 0..<3 {
            current = try await world.service.submit(
                SceneTurnSubmission(
                    characterID: floor.characterID, responseID: floor.responseID, text: "More?"),
                to: current.sceneID
            ).scene
            floor = try #require(current.floor)
        }
        #expect(current.closeReason == nil)
    }

    @Test("A room that cannot be readied says why, on the timeline, the moment the scene opens")
    func stageProblemIsAnnounced() async throws {
        let world = makeWorld()
        await world.performer.setStageProblem(
            "Creature 4754fc0e is not registered with a universe. Is the controller online?")
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let problem = try #require(
            await world.announced.events.first { $0.type == SceneService.stageProblemEventType })
        #expect(problem.payload["scene_id"] == .string(scene.sceneID.rawValue))
        #expect(
            problem.payload["message"]
                == .string(
                    "Creature 4754fc0e is not registered with a universe. Is the controller online?"
                ))
        // The scene itself goes on: the floor was still offered.
        #expect(scene.floor?.characterID == beaky)
    }

    @Test("The house asks; the lead may stay quiet, with a reason the world keeps")
    func houseConsiderationDeclined() async throws {
        let world = makeWorld(limits: SceneLimits(houseMaximumTurns: 3, turnLeadSeconds: 3_600))
        let asked = SceneTrigger(
            kind: .houseConsideration, eventID: .generated(),
            text: "Something just moved in the kitchen.")
        var scene = try await world.service.open(
            regionID: home, conversationID: conversation, trigger: asked,
            participants: [beaky, mango, kenny])
        #expect(try await world.service.hasOpenScene(in: home))
        let floor = try #require(scene.floor)
        scene = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: floor.responseID, text: nil,
                quietReason: "April is in the kitchen; nothing to say"),
            to: scene.sceneID
        ).scene

        // No fallback line, nobody else offered, the scene is closed as declined, and the
        // reason is on the record.
        #expect(scene.state == .abandoned)
        #expect(scene.closeReason == .declined)
        #expect(scene.turns.count == 1)
        #expect(scene.turns[0].isPass)
        #expect(scene.turns[0].quietReason == "April is in the kitchen; nothing to say")
        #expect(await world.announced.offers.count == 1)
        let declined = try #require(
            await world.announced.events.first { $0.type == SceneService.remarkDeclinedEventType })
        #expect(declined.payload["reason"] == .string("April is in the kitchen; nothing to say"))
        #expect(declined.payload["trigger"] == .string("Something just moved in the kitchen."))
        #expect(!(try await world.service.hasOpenScene(in: home)))

        // When the lead does speak, it is an ordinary short house scene: the others follow.
        let spoken = try await world.service.open(
            regionID: home, conversationID: conversation, trigger: asked,
            participants: [beaky, mango])
        let lead = try #require(spoken.floor)
        let after = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: lead.responseID,
                text: "Someone is in the kitchen and it is not me."),
            to: spoken.sceneID
        ).scene
        #expect(after.floor?.characterID == mango)
        #expect(after.closeReason == nil)
    }

    @Test("A pass in an ordinary scene keeps its reason, for the Viewer")
    func passReasonIsKept() async throws {
        let world = makeWorld()
        let scene = try await world.service.open(
            regionID: home, conversationID: conversation,
            trigger: makeTrigger(addressee: beaky), participants: [beaky, mango])
        let floor = try #require(scene.floor)
        let after = try await world.service.submit(
            SceneTurnSubmission(
                characterID: beaky, responseID: floor.responseID, text: nil,
                quietReason: "April was only telling me about the groceries"),
            to: scene.sceneID
        ).scene
        #expect(after.turns[0].isPass)
        #expect(after.turns[0].quietReason == "April was only telling me about the groceries")
        let turnEvent = try #require(
            await world.announced.events.last { $0.type == SceneService.turnEventType })
        #expect(
            turnEvent.payload["quiet_reason"]
                == .string("April was only telling me about the groceries"))
        // Not a declined house question: the scene goes on to Mango.
        #expect(after.closeReason == nil)
        #expect(after.floor?.characterID == mango)
    }

    @Test("Spoken time is estimated from sentences and characters, as the room really speaks")
    func spokenTimeEstimate() {
        // Fitted to Creature Server's frame counts for a real scene: "Kenny loves popcorn
        // too!" rendered to 1.58 s; a 94-character line to 5.02 s.
        let limits = SceneLimits()
        #expect(abs(limits.spokenSeconds(of: "Kenny loves popcorn too!") - 1.55) < 0.01)
        let long =
            "Linux would make the popcorn button reliable, auditable, and free of proprietary kernel p."
        #expect(long.count == 90)
        #expect(abs(limits.spokenSeconds(of: long) - 4.85) < 0.01)
        // Two sentences pay the per-sentence cost twice; nothing to say costs nothing.
        #expect(
            limits.spokenSeconds(of: "I love you too, April. Always, my wizard.")
                > limits.spokenSeconds(of: "I love you too, April, always, my wizard."))
        #expect(limits.spokenSeconds(of: "  ") == 0)
        // A voice with its own pace: Kenny's drawl at eleven a second.
        let drawl = SceneLimits(
            voices: ["character:kenny": SpeakingPace(charactersPerSecond: 11, sentenceSeconds: 0.4)]
        )
        let kenny = try! EntityID(validating: "character:kenny")
        #expect(abs(drawl.spokenSeconds(of: "Kenny loves popcorn too!", by: kenny) - 2.58) < 0.01)
        #expect(abs(drawl.spokenSeconds(of: "Kenny loves popcorn too!") - 1.55) < 0.01)
    }

    @Test("Scene limits decode voices with their own pace")
    func voicesDecode() throws {
        let json = """
            {"turn_lead_seconds": 2, "voices": {"character:kenny": {"characters_per_second": 11, "sentence_seconds": 0.4}}}
            """
        let limits = try JSONDecoder().decode(SceneLimits.self, from: Data(json.utf8))
        #expect(limits.voices["character:kenny"]?.charactersPerSecond == 11)
        #expect(limits.charactersPerSecond == 20)
    }

    /// The default test world offers the next floor at once (a lead longer than any line);
    /// `floorIsPacedToPlayback` covers the real pacing.
    private func makeWorld(
        limits: SceneLimits = SceneLimits(turnLeadSeconds: 3_600), performerFails: Bool = false
    ) -> TestWorld {
        let announced = AnnouncedEvents()
        let timers = ScheduledTimers()
        let recorded = RecordedTurns()
        let performer = FakePerformer(fails: performerFails)
        let clock = ManualWorldClock(now: Self.now)
        let service = SceneService(
            repository: InMemoryScenes(),
            clock: clock,
            limits: limits,
            performer: performer,
            announce: { await announced.record($0) },
            scheduleDeadline: { await timers.schedule($0) },
            cancelDeadline: { await timers.cancel($0) },
            recordTurn: { _, turn in
                await recorded.record(turn)
                return .generated()
            }
        )
        return TestWorld(
            service: service, announced: announced, timers: timers, recorded: recorded,
            performer: performer, clock: clock)
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
    private(set) var canceled: [TimerID] = []
    func schedule(_ timer: WorldTimer) { scheduled.append(timer) }
    func cancel(_ timerID: TimerID) { canceled.append(timerID) }
}

private actor RecordedTurns {
    private(set) var turns: [SceneTurn] = []
    var count: Int { turns.count }
    func record(_ turn: SceneTurn) { turns.append(turn) }
}

private actor FakePerformer: ScenePerforming {
    private(set) var opened: [SceneID] = []
    private(set) var spoken: [SceneTurn] = []
    private(set) var performed: [Scene] = []
    private let fails: Bool
    /// What the room says when it cannot be readied; nil when it can.
    var stageProblem: String?

    init(fails: Bool) { self.fails = fails }

    func setStageProblem(_ problem: String?) { stageProblem = problem }

    func sceneOpened(_ scene: Scene) -> String? {
        opened.append(scene.sceneID)
        return stageProblem
    }

    private(set) var pieces: [(ResponseID, String)] = []
    func sceneTurnPiece(_ scene: Scene, character: EntityID, responseID: ResponseID, text: String) {
        pieces.append((responseID, text))
    }
    private(set) var streamedTurns: [SceneTurn] = []
    func sceneTurn(_ scene: Scene, _ turn: SceneTurn, streamed: Bool) {
        if streamed { streamedTurns.append(turn) } else { spoken.append(turn) }
    }

    func sceneClosed(_ scene: Scene) async throws -> ScenePerformance {
        if fails { throw WorldContractError.invalidScene }
        performed.append(scene)
        return ScenePerformance(
            state: .performed, providerReference: "animation:scene", occurredAt: scene.openedAt)
    }
}

extension Array {
    fileprivate func last(_ n: Int) -> [Element] { Array(suffix(n)) }
}

import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_agent

@Suite("Beaky's mind")
struct CharacterMindTests {
    private let now = Date(timeIntervalSince1970: 1_789_200_000)

    @Test("The transcript is the canonical conversation in order, newest last, bounded")
    func transcriptFollowsCanonicalHistory() throws {
        let mind = makeMind(maximumContextTurns: 3) { _ in "unused" }
        let percept = try makePercept(
            text: "What do you think?",
            prior: [
                ("person", "one", 1), ("character", "two", 2), ("person", "three", 3),
                ("character", "four", 4),
            ]
        )

        let transcript = mind.makeTranscript(for: percept)

        #expect(transcript.first?.role == .system)
        #expect(transcript.first?.content.contains(CharacterMind.contract) == true)
        #expect(transcript.first?.content.hasPrefix("You are Beaky.") == true)
        // The window of three opens on Beaky's "two", which is dropped so April speaks first.
        #expect(transcript.dropFirst().map(\.role) == [.user, .assistant, .user])
        #expect(transcript.dropFirst().map(\.content) == ["three", "four", "What do you think?"])
    }

    @Test("Consecutive messages from one author become one turn so chat templates accept them")
    func consecutiveTurnsAreCoalesced() throws {
        let mind = makeMind { _ in "unused" }
        let percept = try makePercept(
            text: "Hi",
            prior: [
                ("person", "Hello", 1), ("person", "Nice", 2), ("person", "Yay push is working", 3),
                ("character", "Bawk!", 4), ("character", "I mean hello.", 5), ("person", "Woot", 6),
            ]
        )

        let turns = mind.makeTranscript(for: percept).dropFirst()

        #expect(turns.map(\.role) == [.user, .assistant, .user])
        #expect(
            turns.map(\.content) == [
                "Hello\nNice\nYay push is working", "Bawk!\nI mean hello.", "Woot\nHi",
            ])
    }

    @Test("A context window that opens on Beaky's own turn is trimmed to start with April")
    func windowOpensWithApril() throws {
        // Found live on fuzzball: once the bounded window began with a character turn, Mistral's
        // template rejected the transcript ("roles must alternate") and Beaky fell silent.
        let mind = makeMind(maximumContextTurns: 3) { _ in "unused" }
        let percept = try makePercept(
            text: "Still there?",
            prior: [
                ("person", "Hello", 1), ("character", "Hi April!", 2), ("person", "Nice", 3),
                ("character", "Thanks!", 4),
            ]
        )

        let turns = Array(mind.makeTranscript(for: percept).dropFirst())

        #expect(turns.first?.role == .user)
        #expect(turns.map(\.role) == [.user, .assistant, .user])
        #expect(turns.map(\.content) == ["Nice", "Thanks!", "Still there?"])
    }

    @Test("A reply becomes a turn addressed to April with a stable response identity")
    func replyBecomesIntent() async throws {
        let mind = makeMind { transcript in
            #expect(transcript.last?.content == "Are you there?")
            return "<think>hmm</think> \"Always, April! 🦜 Where else would I be?\""
        }
        let consideration = try makeConsideration(text: "Are you there?")

        let decision = try await mind.consider(consideration, now: now)

        guard case .reply(let intent) = decision else {
            Issue.record("Expected a reply, got \(decision)")
            return
        }
        #expect(intent.text == "Always, April! Where else would I be?")
        #expect(intent.conversationID == consideration.percept.utterance.conversationID)
        #expect(intent.characterID.rawValue == "character:beaky")
        #expect(intent.recipientID.rawValue == "person:april")
        #expect(intent.inResponseToUtteranceID == consideration.percept.utterance.utteranceID)
        #expect(intent.reasonReferences == [.event(consideration.envelope.eventID)])
        #expect(
            intent.responseID
                == CharacterMind.responseID(for: consideration.percept.considerationID)
        )
        #expect(
            CharacterMind.responseID(for: consideration.percept.considerationID)
                == CharacterMind.responseID(for: consideration.percept.considerationID)
        )
        #expect(intent.responseID.rawValue.hasPrefix("response:"))
    }

    @Test(
        "The model may decline, or fail to say anything usable",
        arguments: [
            ("[silence]", CharacterDecision.SilenceReason.choseSilence),
            ("  [SILENCE].  ", .choseSilence),
            ("<think>nothing to add</think>[silence]", .choseSilence),
            ("", .emptyResponse),
            ("🦜🦜🦜", .emptyResponse),
            ("<think>only thoughts</think>", .emptyResponse),
        ]
    )
    func modelOutputThatIsNotATurn(raw: String, reason: CharacterDecision.SilenceReason)
        async throws
    {
        let mind = makeMind { _ in raw }

        let decision = try await mind.consider(try makeConsideration(text: "Hi"), now: now)

        #expect(decision == .silence(reason: reason))
    }

    @Test("Old messages and other people's messages are recorded silences, not model calls")
    func guardrailsRunBeforeTheModel() async throws {
        let calls = CallCounter()
        let mind = makeMind { _ in
            await calls.increment()
            return "should not be asked"
        }

        let stale = try makeConsideration(
            text: "Hello?", occurredAt: now.addingTimeInterval(-7_200))
        #expect(try await mind.consider(stale, now: now) == .silence(reason: .stale))

        let stranger = try makeConsideration(text: "Hello?", speaker: "person:jesse")
        #expect(try await mind.consider(stranger, now: now) == .silence(reason: .notAddressed))

        #expect(await calls.value == 0)
    }

    @Test("A model that does not answer in time is a recorded silence")
    func modelTimeoutIsSilence() async throws {
        let mind = makeMind(modelTimeout: .milliseconds(50)) { _ in
            try await Task.sleep(for: .seconds(5))
            return "too late"
        }

        let decision = try await mind.consider(try makeConsideration(text: "Quick!"), now: now)

        #expect(decision == .silence(reason: .modelUnavailable))
    }

    @Test("An over-long answer is cut at a sentence so the world can carry it")
    func overLongAnswersAreTruncatedAtSentence() {
        let sentence = "Bawk, that is a very long thought about robot parts. "
        let long = String(repeating: sentence, count: 120)

        let validated = CharacterMind.validate(long, spokenBy: "beaky")

        #expect(validated != nil)
        #expect(
            validated!.unicodeScalars.count <= ConversationContractLimits.maximumTextUnicodeScalars)
        #expect(validated!.hasSuffix("."))
    }

    @Test("Silence in any dress is a pass, never a spoken word (#162)")
    func silenceInAnyDressIsSilence() {
        for reply in [
            "[silence]", "Silence", "*silence*", "(silence)", " \"SILENCE.\" ", "[Silence]!",
            "Beaky: [Silence]", "Beaky: silence",
        ] {
            #expect(CharacterMind.declinesToSpeak(reply), "\(reply) should be silence")
            #expect(CharacterMind.validate(reply, spokenBy: "beaky") == nil)
        }
        #expect(!CharacterMind.declinesToSpeak("Silence is golden, April."))
        #expect(!CharacterMind.declinesToSpeak("Beaky: Silence is golden."))
        #expect(CharacterMind.validate("Silence is golden, April.", spokenBy: "beaky") != nil)
    }

    @Test("A reply written as a script line keeps only her words (#154)")
    func speakerLabelsAreDropped() {
        #expect(
            CharacterMind.validate("Beaky: \"That sounds like fun, April!\"", spokenBy: "beaky")
                == "That sounds like fun, April!")
        #expect(
            CharacterMind.validate("  BEAKY said: Bawk, hello.", spokenBy: "beaky")
                == "Bawk, hello.")
        #expect(
            CharacterMind.validate("Beaky is my name and I like it.", spokenBy: "beaky")
                == "Beaky is my name and I like it.")
        #expect(
            CharacterMind.validate("April: are you there?", spokenBy: "beaky")
                == "April: are you there?")
    }

    // MARK: - The room

    @Test("In the room, Beaky speaks sentence by sentence while the model is still thinking")
    func speaksInTheRoomWhileGenerating() async throws {
        let room = FakeRoom(animationID: "animation:7")
        let stager = FakeStager(route: .physicalSpeech)
        let mind = makeMind(
            stage: CharacterMind.Stage(
                stager: stager, room: room,
                respondStreaming: { _ in
                    AsyncStream { continuation in
                        continuation.yield("Beaky: \"Bawk, hello April!")
                        continuation.yield("The servos look great 🎉.")
                        continuation.finish()
                    }
                })
        ) { _ in "unused" }

        let decision = try await mind.consider(try makeConsideration(text: "Look!"), now: now)

        guard case .performed(let performance) = decision else {
            Issue.record("expected a performed turn, got \(decision)")
            return
        }
        #expect(await room.spoken == ["Bawk, hello April!", "The servos look great ."])
        #expect(await room.sessionsOpened == 1)
        #expect(performance.intent.text == "Bawk, hello April! The servos look great .")
        #expect(performance.attemptID == stager.attemptID)
        #expect(performance.outcome.state == .performed)
        #expect(performance.outcome.providerReference == "animation:7")
        #expect(await stager.requests.count == 1)
        #expect(await stager.requests.first?.responseID == performance.intent.responseID)
    }

    @Test("Silence in the room never opens a session")
    func silenceNeverOpensTheRoom() async throws {
        let room = FakeRoom(animationID: "animation:8")
        let mind = makeMind(
            stage: CharacterMind.Stage(
                stager: FakeStager(route: .physicalSpeech), room: room,
                respondStreaming: { _ in
                    AsyncStream { continuation in
                        continuation.yield("[silence]")
                        continuation.finish()
                    }
                })
        ) { _ in "unused" }

        let decision = try await mind.consider(try makeConsideration(text: "meh"), now: now)

        #expect(decision == .silence(reason: .choseSilence))
        #expect(await room.sessionsOpened == 0)
        #expect(await room.spoken.isEmpty)
    }

    @Test("When the room cannot speak, the turn is still recorded as a failed performance")
    func roomFailureIsRecorded() async throws {
        let room = FakeRoom(animationID: nil, failure: .sessionStartFailed("server down"))
        let mind = makeMind(
            stage: CharacterMind.Stage(
                stager: FakeStager(route: .physicalSpeech), room: room,
                respondStreaming: { _ in
                    AsyncStream { continuation in
                        continuation.yield("I would have said this.")
                        continuation.finish()
                    }
                })
        ) { _ in "unused" }

        let decision = try await mind.consider(try makeConsideration(text: "Hi"), now: now)

        guard case .performed(let performance) = decision else {
            Issue.record("expected a performed turn, got \(decision)")
            return
        }
        #expect(performance.outcome.state == .failed)
        #expect(performance.outcome.errorCode == "physical_speech_start_failed")
        #expect(performance.intent.text == "I would have said this.")
    }

    @Test("When the world says Communicator, the whole reply goes to the world for routing")
    func communicatorStageRepliesThroughTheWorld() async throws {
        let room = FakeRoom(animationID: "animation:9")
        let mind = makeMind(
            stage: CharacterMind.Stage(
                stager: FakeStager(route: .communicator), room: room,
                respondStreaming: { _ in AsyncStream { $0.finish() } })
        ) { transcript in
            #expect(transcript.first?.content.contains("Beaky Communicator app") == true)
            return "Text me back when you are home."
        }

        let decision = try await mind.consider(try makeConsideration(text: "Hi"), now: now)

        guard case .reply(let intent) = decision else {
            Issue.record("expected a reply, got \(decision)")
            return
        }
        #expect(intent.text == "Text me back when you are home.")
        #expect(await room.sessionsOpened == 0)
    }

    @Test("A turn the world already carried is not performed again")
    func alreadyDeliveredTurnIsNotRepeated() async throws {
        let room = FakeRoom(animationID: "animation:10")
        let stager = FakeStager(route: .physicalSpeech, alreadyDelivered: true)
        let mind = makeMind(
            stage: CharacterMind.Stage(
                stager: stager, room: room,
                respondStreaming: { _ in AsyncStream { $0.finish() } })
        ) { _ in "unused" }

        let decision = try await mind.consider(try makeConsideration(text: "Hi"), now: now)

        guard case .alreadyDelivered = decision else {
            Issue.record("expected already delivered, got \(decision)")
            return
        }
        #expect(await room.sessionsOpened == 0)
    }

    @Test("The room's contract tells Beaky April can hear her")
    func roomContractSaysAprilIsPresent() throws {
        let mind = makeMind { _ in "unused" }
        let percept = try makePercept(text: "Hi")

        let room = mind.makeTranscript(for: percept, route: .physicalSpeech)
        let app = mind.makeTranscript(for: percept, route: .communicator)

        #expect(room.first?.content.contains("in the room with you") == true)
        #expect(app.first?.content.contains("Beaky Communicator app") == true)
    }

    // MARK: - Helpers

    private func makeMind(
        maximumContextTurns: Int = 20,
        modelTimeout: Duration = .seconds(5),
        stage: CharacterMind.Stage? = nil,
        respond: @escaping CharacterMind.Respond
    ) -> CharacterMind {
        CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: .text("You are Beaky."),
                characterID: try! EntityID(validating: "character:beaky"),
                personID: try! EntityID(validating: "person:april"),
                maximumReplyAge: 3_600,
                maximumContextTurns: maximumContextTurns,
                modelTimeout: modelTimeout,
                modelName: "test-model"
            ),
            respond: respond,
            stage: stage,
            logger: Logger(label: "character-mind-tests")
        )
    }

    private func makePercept(
        text: String,
        speaker: String = "person:april",
        occurredAt: Date? = nil,
        prior: [(kind: String, text: String, at: Int)] = []
    ) throws -> PersonUtterancePercept {
        let conversationID = try ConversationID(validating: "conversation:april-beaky")
        let utterance = try PersonUtterance(
            conversationID: conversationID,
            speakerID: EntityID(validating: speaker),
            addresseeIDs: [EntityID(validating: "character:beaky")],
            text: text,
            modality: .typed,
            source: .communicatorComposition,
            sourceID: SourceID(validating: "communicator:test"),
            occurredAt: occurredAt ?? now.addingTimeInterval(-2),
            confidence: 1
        )
        let items = try prior.map { entry in
            try ConversationItem(
                conversationID: conversationID,
                authorID: EntityID(
                    validating: entry.kind == "person" ? "person:april" : "character:beaky"),
                authorKind: entry.kind == "person" ? .person : .character,
                text: entry.text,
                createdAt: Date(timeIntervalSince1970: TimeInterval(entry.at)),
                utteranceID: entry.kind == "person" ? .generated() : nil,
                responseID: entry.kind == "person" ? nil : .generated()
            )
        }
        return try PersonUtterancePercept(
            characterID: EntityID(validating: "character:beaky"),
            utterance: utterance,
            priorConversationItems: items
        )
    }

    private func makeConsideration(
        text: String,
        speaker: String = "person:april",
        occurredAt: Date? = nil
    ) throws -> WorldConsideration {
        let percept = try makePercept(text: text, speaker: speaker, occurredAt: occurredAt)
        let envelope = try WorldEventEnvelope(
            occurredAt: percept.utterance.occurredAt,
            source: EventSource(id: percept.utterance.sourceID, kind: "test"),
            subjectIDs: [percept.utterance.speakerID, percept.characterID],
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: percept
        )
        return WorldConsideration(worldSequence: 42, envelope: envelope, percept: percept)
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// A room that remembers what it was asked to say.
private actor FakeRoom: PhysicalSpeechStaging {
    private(set) var spoken: [String] = []
    private(set) var sessionsOpened = 0
    private let animationID: String?
    private let failure: PhysicalSpeechStageError?

    init(animationID: String?, failure: PhysicalSpeechStageError? = nil) {
        self.animationID = animationID
        self.failure = failure
    }

    func perform(_ sentences: AsyncStream<String>) async throws -> String? {
        for await sentence in sentences {
            if let failure { throw failure }
            if spoken.isEmpty { sessionsOpened += 1 }
            spoken.append(sentence)
        }
        return spoken.isEmpty ? nil : animationID
    }
}

/// A world that always puts Beaky on one stage.
private actor FakeStager: WorldStaging {
    let attemptID = try! DeliveryAttemptID(validating: "delivery-attempt:test")
    private let route: CharacterDeliveryRoute
    private let alreadyDelivered: Bool
    private(set) var requests: [CharacterStageRequest] = []

    init(route: CharacterDeliveryRoute, alreadyDelivered: Bool = false) {
        self.route = route
        self.alreadyDelivered = alreadyDelivered
    }

    func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) throws -> CharacterStageResult {
        requests.append(request)
        let now = Date(timeIntervalSince1970: 1_789_200_000)
        let home = route == .physicalSpeech
        let decision = try CharacterDeliveryDecision(
            attemptID: attemptID,
            responseID: request.responseID,
            route: route,
            privacyMode: home ? .notApplicable : .private,
            reason: home ? .homeAndAudible : .presenceUncertain,
            decidedAt: now,
            presence: PersonPresence(
                personID: request.recipientID, state: home ? .home : .unknown,
                confidence: home ? 1 : 0, observedAt: now, validUntil: now,
                physicallyAudible: home, basis: .assumed)
        )
        return CharacterStageResult(
            disposition: alreadyDelivered ? .alreadyDelivered : .decided, decision: decision)
    }
}

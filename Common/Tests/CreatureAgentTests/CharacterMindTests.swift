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

        let decision = await mind.consider(consideration, now: now)

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

        let decision = await mind.consider(try makeConsideration(text: "Hi"), now: now)

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
        #expect(await mind.consider(stale, now: now) == .silence(reason: .stale))

        let stranger = try makeConsideration(text: "Hello?", speaker: "person:jesse")
        #expect(await mind.consider(stranger, now: now) == .silence(reason: .notAddressed))

        #expect(await calls.value == 0)
    }

    @Test("A model that does not answer in time is a recorded silence")
    func modelTimeoutIsSilence() async throws {
        let mind = makeMind(modelTimeout: .milliseconds(50)) { _ in
            try await Task.sleep(for: .seconds(5))
            return "too late"
        }

        let decision = await mind.consider(try makeConsideration(text: "Quick!"), now: now)

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

    // MARK: - Helpers

    private func makeMind(
        maximumContextTurns: Int = 20,
        modelTimeout: Duration = .seconds(5),
        respond: @escaping CharacterMind.Respond
    ) -> CharacterMind {
        CharacterMind(
            configuration: CharacterMind.Configuration(
                persona: "You are Beaky.",
                characterID: try! EntityID(validating: "character:beaky"),
                personID: try! EntityID(validating: "person:april"),
                maximumReplyAge: 3_600,
                maximumContextTurns: maximumContextTurns,
                modelTimeout: modelTimeout,
                modelName: "test-model"
            ),
            respond: respond,
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

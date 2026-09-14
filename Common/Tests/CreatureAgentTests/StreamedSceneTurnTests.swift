import Foundation
import Logging
import Testing
import WorldCore

@testable import creature_agent

@Suite("Scene turns, sentence by sentence")
struct StreamedSceneTurnTests {
    private let now = Date(timeIntervalSince1970: 1_789_600_000)
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")
    private let april = try! EntityID(validating: "person:april")

    @Test("Each sentence goes to the world as it is composed; the turn then says it is done")
    func sentencesAreSpokenAsTheyLand() async throws {
        let mind = makeMind(sentences: [
            "Beaky: April, not quite, Kenny.", "The front door was unlocked,",
            "*ruffles feathers* but I do not know that it opened.",
        ])
        let spoken = Spoken()

        let decision = try await mind.consider(try makeOffer(), now: now) { index, text in
            await spoken.record(index, text)
        }

        #expect(
            await spoken.pieces
                == [
                    (0, "Not quite, Kenny."), (1, "The front door was unlocked,"),
                    (2, "but I do not know that it opened."),
                ].map { "\($0.0):\($0.1)" })
        guard case .turn(let done) = decision else {
            Issue.record("expected a turn")
            return
        }
        #expect(done.text == nil)
        #expect(done.piece == nil)
        #expect(done.responseID == (try makeOffer()).offer.responseID)
    }

    @Test("Silence first is a pass and nothing is spoken; a bare direction is nothing")
    func silenceIsAPass() async throws {
        let quiet = makeMind(sentences: ["[silence]"])
        let spoken = Spoken()
        let decision = try await quiet.consider(try makeOffer(), now: now) { index, text in
            await spoken.record(index, text)
        }
        guard case .pass(_, let reason) = decision else {
            Issue.record("expected a pass")
            return
        }
        #expect(reason == .choseSilence)
        #expect(await spoken.pieces.isEmpty)

        let onlyDirection = makeMind(sentences: ["*preens*"])
        guard
            case .pass(_, let empty) = try await onlyDirection.consider(
                try makeOffer(), now: now, speak: { _, _ in })
        else {
            Issue.record("expected a pass")
            return
        }
        #expect(empty == .emptyResponse)
    }

    @Test("When the world cannot take a piece, the turn is retried from the cursor")
    func worldAwayIsRetried() async throws {
        let mind = makeMind(sentences: ["One.", "Two."])
        await #expect(throws: WorldResponderError.self) {
            try await mind.consider(try makeOffer(), now: now) { _, _ in
                throw WorldResponderError.unavailable(status: 503)
            }
        }
    }

    @Test("Without a streaming model the turn is composed whole, as before")
    func wholeLineWithoutStreaming() async throws {
        let mind = CharacterMind(
            configuration: configuration, respond: { _ in "April, all at once." },
            logger: Logger(label: "streamed-scene-tests"))
        guard
            case .turn(let turn) = try await mind.consider(
                try makeOffer(), now: now, speak: { _, _ in })
        else {
            Issue.record("expected a turn")
            return
        }
        #expect(turn.text == "All at once.")
        #expect(turn.piece == nil)
    }

    private var configuration: CharacterMind.Configuration {
        CharacterMind.Configuration(
            persona: .text("You are Beaky."), characterID: beaky, personID: april,
            maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
            modelName: "test")
    }

    private func makeMind(sentences: [String]) -> CharacterMind {
        CharacterMind(
            configuration: configuration,
            respond: { _ in sentences.joined(separator: " ") },
            respondStreaming: { _ in
                AsyncStream { continuation in
                    for sentence in sentences { continuation.yield(sentence) }
                    continuation.finish()
                }
            },
            logger: Logger(label: "streamed-scene-tests"))
    }

    private func makeOffer() throws -> WorldSceneConsideration {
        let offer = try SceneTurnOffer(
            sceneID: SceneID(validating: "scene:streamed"),
            characterID: beaky,
            responseID: ResponseID(validating: "response:streamed"),
            deadline: now.addingTimeInterval(8),
            trigger: SceneTrigger(
                kind: .personUtterance, eventID: .generated(), speakerID: april,
                text: "What just happened?"),
            participants: [beaky, mango], turns: [])
        let envelope = try WorldEventEnvelope(
            occurredAt: now,
            source: EventSource(id: SourceID(validating: "world:scenes"), kind: "world"),
            subjectIDs: [beaky],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: offer)
        return WorldSceneConsideration(worldSequence: 1, envelope: envelope, offer: offer)
    }
}

private actor Spoken {
    private(set) var pieces: [String] = []
    func record(_ index: Int, _ text: String) { pieces.append("\(index):\(text)") }
}

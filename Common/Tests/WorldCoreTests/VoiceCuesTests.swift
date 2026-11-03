import Foundation
import Testing

@testable import WorldCore

@Suite("Voice cues (#270)")
struct VoiceCuesTests {
    @Test("A cue is a sound or a feeling in brackets; the minds' tags and narration are not")
    func whatIsACue() {
        #expect(VoiceCues.cues(in: "I don't believe it. [sighs] Fine.") == ["[sighs]"])
        #expect(
            VoiceCues.cues(in: "[choked up with happiness] Oh, April.")
                == ["[choked up with happiness]"])
        #expect(
            VoiceCues.cues(in: "[laughs] Yes. [clears throat] No.") == [
                "[laughs]", "[clears throat]",
            ])
        // The protocol tags all carry a colon, and silence is the silence token.
        #expect(VoiceCues.cues(in: "[learned: April | likes | tea] Lovely.").isEmpty)
        #expect(VoiceCues.cues(in: "[house: Movie Time] Popcorn!").isEmpty)
        #expect(VoiceCues.cues(in: "[quiet: nothing to add]").isEmpty)
        #expect(VoiceCues.cues(in: "[silence]").isEmpty)
        #expect(VoiceCues.cues(in: "[ Silence ]").isEmpty)
        // Not a feeling at all, and too long to be one.
        #expect(VoiceCues.cues(in: "Item [42] is here.").isEmpty)
        #expect(VoiceCues.cues(in: "[ ] hello").isEmpty)
        #expect(
            VoiceCues.cues(
                in: "[hops onto the perch and flaps both wings very hard] Hi."
            ).isEmpty)
    }

    @Test("A line's words are the line without its cues, with no space left before punctuation")
    func words() {
        #expect(
            VoiceCues.words("I don't believe it. [sighs] Fine, we'll try again.")
                == "I don't believe it. Fine, we'll try again.")
        #expect(VoiceCues.words("Fine [sighs].") == "Fine.")
        #expect(VoiceCues.words("[gasps]") == "")
        // A line with no cue is its own words, exactly.
        #expect(VoiceCues.words("The servos look great .") == "The servos look great .")
        #expect(VoiceCues.words("[house: Movie Time] Popcorn!") == "[house: Movie Time] Popcorn!")
    }

    @Test("A line keeps its first cue, or none")
    func keepingFirst() {
        let line = "[sighs] Fine. [laughs] Okay, okay."
        #expect(VoiceCues.keepingFirst(line) == "[sighs] Fine. Okay, okay.")
        #expect(VoiceCues.keepingFirst(line, allowed: false) == "Fine. Okay, okay.")
        #expect(VoiceCues.keepingFirst("No cue here.") == "No cue here.")
    }

    @Test("A cue is paced as its performance, not as its letters")
    func pacing() throws {
        let limits = SceneLimits()
        let words = "Fine, we'll try again."
        // Twenty-six letters would read as 1.3 s; the cue adds what it measured.
        #expect(
            abs(
                limits.spokenSeconds(of: "[choked up with happiness] " + words)
                    - (limits.spokenSeconds(of: words) + limits.cueSeconds)) < 0.001)
        #expect(limits.spokenSeconds(of: "[sighs]") == 0)
        #expect(limits.cueSeconds == 0.75)
        let tuned = try JSONDecoder().decode(
            SceneLimits.self, from: Data(#"{"cue_seconds": 1.2}"#.utf8))
        #expect(tuned.cueSeconds == 1.2)
    }

    @Test("The performed line rides beside the words, and an old record has none")
    func performedRoundTrips() throws {
        let item = try ConversationItem(
            conversationID: ConversationID(validating: "conversation:house"),
            authorID: EntityID(validating: "character:beaky"),
            authorKind: .character,
            text: "Fine, we'll try again.",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            responseID: .generated(),
            performed: "[sighs] Fine, we'll try again."
        )
        let encoder = WorldJSON.makeEncoder()
        let decoder = WorldJSON.makeDecoder()
        let decoded = try decoder.decode(ConversationItem.self, from: encoder.encode(item))
        #expect(decoded == item)
        #expect(decoded.performed == "[sighs] Fine, we'll try again.")

        var plain = item
        plain.performed = nil
        let json = String(decoding: try encoder.encode(plain), as: UTF8.self)
        #expect(!json.contains("performed"))
        #expect(try decoder.decode(ConversationItem.self, from: Data(json.utf8)).performed == nil)

        let intent = try CharacterUtteranceIntent(
            conversationID: item.conversationID,
            characterID: item.authorID,
            recipientID: EntityID(validating: "person:april"),
            text: item.text,
            urgency: 0.3,
            createdAt: item.createdAt,
            performed: item.performed
        )
        #expect(
            try decoder.decode(CharacterUtteranceIntent.self, from: encoder.encode(intent))
                .performed == item.performed)

        let turn = SceneTurn(
            characterID: item.authorID, responseID: .generated(), text: item.text,
            performed: item.performed, offeredAt: item.createdAt, answeredAt: item.createdAt)
        #expect(try decoder.decode(SceneTurn.self, from: encoder.encode(turn)) == turn)
        #expect(turn.spoken == item.performed)
    }
}

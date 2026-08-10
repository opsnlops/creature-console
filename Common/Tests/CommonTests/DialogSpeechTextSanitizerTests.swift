import Foundation
import Testing

@testable import Common

@Suite("Dialog speech text sanitizer")
struct DialogSpeechTextSanitizerTests {

    @Test("leaves ordinary text and style tags unchanged")
    func leavesOrdinaryTextUnchanged() {
        let text = "[whispers] Beaky, don't touch that!"
        #expect(DialogSpeechTextSanitizer.sanitize(text) == text)
    }

    @Test("normalizes common pasted punctuation")
    func normalizesPastedPunctuation() {
        let text = "“Wait—don’t…” «Really?»"
        #expect(DialogSpeechTextSanitizer.sanitize(text) == "\"Wait-don't...\" \"Really?\"")
    }

    @Test("removes parenthesis delimiters without removing spoken words")
    func removesParenthesisDelimiters() {
        let text = "[whispers] (He was Unitarian) and （so was she）."
        #expect(
            DialogSpeechTextSanitizer.sanitize(text)
                == "[whispers] He was Unitarian and so was she.")
    }

    @Test("collapses Unicode whitespace and trims the result")
    func collapsesWhitespace() {
        let text = "  hello\u{00A0}\u{2003}\n\tworld  "
        #expect(DialogSpeechTextSanitizer.sanitize(text) == "hello world")
    }

    @Test("removes invisible formatting and separates control-delimited words")
    func removesInvisibleCharacters() {
        let text = "zero\u{200B}width\u{0000}next\u{FEFF}word\u{FFFD}"
        #expect(DialogSpeechTextSanitizer.sanitize(text) == "zero width nextword")
    }

    @Test("uses canonical Unicode composition without removing international letters")
    func preservesInternationalLetters() {
        let decomposed = "Cafe\u{0301} Māori 日本語"
        #expect(DialogSpeechTextSanitizer.sanitize(decomposed) == "Café Māori 日本語")
    }

    @Test("sanitization is idempotent")
    func isIdempotent() {
        let once = DialogSpeechTextSanitizer.sanitize("  “hello…”\u{200B}  ")
        #expect(DialogSpeechTextSanitizer.sanitize(once) == once)
    }

    @Test("script cleanup changes only turn text")
    func scriptCleanupPreservesMetadata() {
        let id = UUID()
        let stageId = UUID()
        let turn = DialogScriptTurn(creatureId: "beaky", text: "  I’m here…  ")
        let script = DialogScript(
            id: id,
            title: "Title — unchanged",
            notes: "Notes\nremain formatted",
            turns: [turn],
            stageId: stageId,
            createdAt: 10,
            updatedAt: 20
        )

        let sanitized = script.sanitizedForSpeech

        #expect(sanitized.id == id)
        #expect(sanitized.title == script.title)
        #expect(sanitized.notes == script.notes)
        #expect(sanitized.stageId == stageId)
        #expect(sanitized.createdAt == 10)
        #expect(sanitized.updatedAt == 20)
        #expect(sanitized.turns[0].id == turn.id)
        #expect(sanitized.turns[0].creatureId == "beaky")
        #expect(sanitized.turns[0].text == "I'm here...")
    }
}

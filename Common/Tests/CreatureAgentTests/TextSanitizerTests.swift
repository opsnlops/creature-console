import Testing

@testable import creature_agent

@Suite("CreatureAgent TextSanitizer")
struct TextSanitizerTests {
    @Test("Removes emojis and symbols")
    func removesEmojisAndSymbols() {
        let input = "Hello 😊 ⚠️"
        let result = TextSanitizer.sanitize(input)
        #expect(result.text == "Hello")
        #expect(result.removedCharacters > 0)
    }

    @Test("Keeps digits, # and *, which Unicode also marks as emoji keycap bases")
    func keepsDigitsAndKeycapBases() {
        let result = TextSanitizer.sanitize("Flight #2 is at 11:30, rated 5* by 3 parrots")
        #expect(result.text == "Flight #2 is at 11:30, rated 5* by 3 parrots")
        #expect(result.removedCharacters == 0)

        let keycap = TextSanitizer.sanitize("Option 1\u{FE0F}\u{20E3} please")
        #expect(keycap.text == "Option 1 please")
    }

    @Test("Preserves common Unicode punctuation")
    func preservesUnicodePunctuation() {
        let input = "April’s here—really."
        let result = TextSanitizer.sanitize(input)
        #expect(result.text == input)
        #expect(result.removedCharacters == 0)
    }

    @Test("Normalizes whitespace and trims")
    func normalizesWhitespace() {
        let input = "  Hello\n\tApril  "
        let result = TextSanitizer.sanitize(input)
        #expect(result.text == "Hello April")
    }

    @Test("Drops control characters")
    func dropsControlCharacters() {
        let input = "Hello\u{0000}April"
        let result = TextSanitizer.sanitize(input)
        #expect(result.text == "HelloApril")
        #expect(result.removedCharacters == 1)
    }

    @Test("Empty input returns empty text")
    func handlesEmptyInput() {
        let result = TextSanitizer.sanitize("")
        #expect(result.text.isEmpty)
        #expect(result.removedCharacters == 0)
    }
}

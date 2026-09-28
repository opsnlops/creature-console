import Testing

@testable import World_Viewer

@Suite("The Mundane view's JSON colors")
struct JSONHighlighterTests {
    @Test("A key, a string value, and the punctuation between, rejoining to the line")
    func keyAndString() {
        let line: Substring = #"    "predicate" : "person.description","#
        let tokens = JSONHighlighter.tokens(of: line)
        #expect(
            tokens == [
                .punctuation("    "), .key(#""predicate""#), .punctuation(" : "),
                .string(#""person.description""#), .punctuation(","),
            ])
        #expect(tokens.map(text).joined() == String(line))
    }

    @Test("Numbers, literals, and escaped quotes inside a string")
    func numbersLiteralsEscapes() {
        #expect(
            JSONHighlighter.tokens(of: #"  "confidence" : -0.95e2,"#) == [
                .punctuation("  "), .key(#""confidence""#), .punctuation(" : "),
                .number("-0.95e2"), .punctuation(","),
            ])
        #expect(
            JSONHighlighter.tokens(of: "  true, false, null") == [
                .punctuation("  "), .literal("true"), .punctuation(", "), .literal("false"),
                .punctuation(", "), .literal("null"),
            ])
        // An escaped quote does not end the string, and a colon inside it is not a key's.
        let quoted: Substring = #""value" : "she said \"hi: there\"""#
        #expect(
            JSONHighlighter.tokens(of: quoted) == [
                .key(#""value""#), .punctuation(" : "), .string(#""she said \"hi: there\"""#),
            ])
    }

    @Test("Brackets and an unterminated string never lose text")
    func bracketsAndUnterminated() {
        #expect(JSONHighlighter.tokens(of: "  ],") == [.punctuation("  ],")])
        let broken: Substring = #""open"#
        #expect(JSONHighlighter.tokens(of: broken).map(text).joined() == String(broken))
    }

    private func text(_ token: JSONHighlighter.Token) -> String {
        switch token {
        case .key(let t), .string(let t), .number(let t), .literal(let t),
            .punctuation(let t):
            t
        }
    }
}

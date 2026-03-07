import Testing

@testable import creature_agent

@Suite("Think tag stripping")
struct ThinkTagStrippingTests {
    @Test("Strips single think block")
    func singleBlock() {
        let input = "<think>reasoning here</think>Hello!"
        let result = LMStudioClient.stripThinkTags(input)
        #expect(result == "Hello!")
    }

    @Test("Strips multiline think block")
    func multilineBlock() {
        let input = """
            <think>
            Let me think about this...
            The answer is 42.
            </think>
            The answer is 42.
            """
        let result = LMStudioClient.stripThinkTags(input)
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "The answer is 42.")
    }

    @Test("Strips multiple think blocks")
    func multipleBlocks() {
        let input = "<think>first</think>Hello <think>second</think>world"
        let result = LMStudioClient.stripThinkTags(input)
        #expect(result == "Hello world")
    }

    @Test("Returns text unchanged when no think tags present")
    func noTags() {
        let input = "Just regular text"
        let result = LMStudioClient.stripThinkTags(input)
        #expect(result == "Just regular text")
    }

    @Test("Handles empty think block")
    func emptyBlock() {
        let input = "<think></think>Content"
        let result = LMStudioClient.stripThinkTags(input)
        #expect(result == "Content")
    }
}

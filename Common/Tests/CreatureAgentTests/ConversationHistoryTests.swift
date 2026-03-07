import Testing

@testable import creature_agent

@Suite("ConversationHistory")
struct ConversationHistoryTests {
    @Test("Returns empty messages initially")
    func emptyState() async {
        let history = ConversationHistory(maxExchanges: 5)
        let messages = await history.allMessages()
        #expect(messages.isEmpty)
    }

    @Test("Appends user and assistant messages")
    func appendMessages() async {
        let history = ConversationHistory(maxExchanges: 5)
        await history.append(userMessage: "Hello", assistantMessage: "Hi there!")
        let messages = await history.allMessages()
        #expect(messages.count == 2)
        #expect(messages[0].role == "user")
        #expect(messages[0].content == "Hello")
        #expect(messages[1].role == "assistant")
        #expect(messages[1].content == "Hi there!")
    }

    @Test("Trims oldest exchanges when exceeding max")
    func windowTrimming() async {
        let history = ConversationHistory(maxExchanges: 2)
        await history.append(userMessage: "First", assistantMessage: "Response 1")
        await history.append(userMessage: "Second", assistantMessage: "Response 2")
        await history.append(userMessage: "Third", assistantMessage: "Response 3")

        let messages = await history.allMessages()
        #expect(messages.count == 4)
        #expect(messages[0].role == "user")
        #expect(messages[0].content == "Second")
        #expect(messages[3].role == "assistant")
        #expect(messages[3].content == "Response 3")
    }
}

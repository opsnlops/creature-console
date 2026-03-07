actor ConversationHistory {
    private var messages: [(role: String, content: String)] = []
    private let maxExchanges: Int

    init(maxExchanges: Int) {
        self.maxExchanges = maxExchanges
    }

    func append(userMessage: String, assistantMessage: String) {
        messages.append((role: "user", content: userMessage))
        messages.append((role: "assistant", content: assistantMessage))

        let maxMessages = maxExchanges * 2
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    func allMessages() -> [(role: String, content: String)] {
        messages
    }
}

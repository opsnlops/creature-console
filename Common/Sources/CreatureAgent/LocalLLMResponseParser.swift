import Foundation

struct LocalLLMResponseParser {
    static func outputText(from data: Data) throws -> String {
        let decoder = JSONDecoder()
        let response = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let choice = response.choices.first,
            let content = choice.message.content,
            !content.isEmpty
        else {
            throw LocalLLMClientError.missingOutputText
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatChoiceMessage
}

private struct ChatChoiceMessage: Decodable {
    let content: String?
}

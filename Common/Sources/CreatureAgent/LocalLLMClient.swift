import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct LocalLLMClient {

    private let host: String
    private let port: Int
    private let model: String
    private let systemPrompt: String
    private let temperature: Double
    private let maxTokens: Int
    private let logger: Logger
    private let traceResponses: Bool
    private let history: ConversationHistory

    init(
        host: String,
        port: Int,
        model: String,
        systemPrompt: String,
        temperature: Double,
        maxTokens: Int,
        conversationHistorySize: Int,
        logger: Logger,
        traceResponses: Bool
    ) {
        self.host = host
        self.port = port
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.logger = logger
        self.traceResponses = traceResponses
        self.history = ConversationHistory(maxExchanges: conversationHistorySize)
    }

    func respond(to prompt: String) async throws -> String {
        guard let url = URL(string: "http://\(host):\(port)/v1/chat/completions") else {
            throw LocalLLMClientError.invalidURL
        }

        logger.debug("Sending local LLM request (model: \(model))")

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        let historyMessages = await history.allMessages()
        for msg in historyMessages {
            messages.append(["role": msg.role, "content": msg.content])
        }

        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stop": ["\n\n\n", "\n\n"],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalLLMClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            logger.error("Local LLM request failed with status \(httpResponse.statusCode)")
            throw LocalLLMClientError.httpError(code: httpResponse.statusCode, body: message)
        }

        if traceResponses, let bodyString = String(data: data, encoding: .utf8) {
            logger.info("Local LLM raw response: \(bodyString)")
        }

        let rawOutput = try LocalLLMResponseParser.outputText(from: data)
        let output = LocalLLMClient.stripThinkTags(rawOutput)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("Local LLM response received (chars: \(output.count))")

        await history.append(userMessage: prompt, assistantMessage: output)

        return output
    }

    internal static func stripThinkTags(_ text: String) -> String {
        let pattern = "<think>[\\s\\S]*?</think>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

enum LocalLLMClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(code: Int, body: String)
    case missingOutputText

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid local LLM URL"
        case .invalidResponse:
            return "Invalid local LLM response"
        case .httpError(let code, let body):
            if body.isEmpty {
                return "Local LLM API returned status \(code)"
            }
            return "Local LLM API returned status \(code): \(body)"
        case .missingOutputText:
            return "Local LLM response did not include output text"
        }
    }
}

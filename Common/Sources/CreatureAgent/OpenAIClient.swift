import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenAI through the Responses API. The MQTT agent uses the one-shot `respond(to:)`; a
/// world-mode mind sends its whole transcript and, in the room, streams sentences as they are
/// composed — the same shape as the local client, so a bird sounds the same whichever model
/// is thinking (April, 2026-09-12: "let's see how GPT 6 does, on low effort").
struct OpenAIClient: Sendable {
    static let defaultEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let logger: Logger
    private let traceResponses: Bool
    private let temperature: Double
    /// `low` / `medium` / `high` for reasoning models; when set, `temperature` is not sent —
    /// reasoning models refuse it.
    private let reasoningEffort: String?
    private let minSentenceChars: Int

    init(
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double,
        reasoningEffort: String? = nil,
        minSentenceChars: Int = 0,
        endpoint: URL = OpenAIClient.defaultEndpoint,
        logger: Logger,
        traceResponses: Bool
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.minSentenceChars = minSentenceChars
        self.logger = logger
        self.traceResponses = traceResponses
    }

    // MARK: - One prompt (MQTT mode)

    func respond(to prompt: String) async throws -> String {
        try await respond(messages: [
            LocalLLMClient.Message(role: .system, content: systemPrompt),
            LocalLLMClient.Message(role: .user, content: prompt),
        ])
    }

    // MARK: - A transcript (world mode)

    func respond(messages transcript: [LocalLLMClient.Message]) async throws -> String {
        logger.debug("Sending OpenAI response request (model: \(model))")
        var request = makeRequest(for: transcript, stream: false)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            logger.error("OpenAI request failed with status \(httpResponse.statusCode)")
            throw OpenAIClientError.httpError(code: httpResponse.statusCode, body: message)
        }
        if traceResponses, let bodyString = String(data: data, encoding: .utf8) {
            logger.info("OpenAI raw response: \(bodyString)")
        }
        let output = try OpenAIResponseParser.outputText(from: data)
        logger.debug("OpenAI response received (chars: \(output.count))")
        return output
    }

    /// Sentences as the model composes them, from the Responses API's SSE stream
    /// (`response.output_text.delta` events carry the text).
    func respondStreaming(messages transcript: [LocalLLMClient.Message]) -> AsyncStream<String> {
        let request = makeRequest(for: transcript, stream: true)
        let logger = self.logger
        let model = self.model
        let traceResponses = self.traceResponses
        let minSentenceChars = self.minSentenceChars
        return AsyncStream { continuation in
            Task {
                logger.debug("Starting streaming OpenAI request (model: \(model))")
                let sseDelegate = SSEDataDelegate()
                let session = URLSession(
                    configuration: .default, delegate: sseDelegate, delegateQueue: nil)
                session.dataTask(with: request).resume()
                defer { session.finishTasksAndInvalidate() }

                var assembler = SentenceAssembler(minimumCharacters: minSentenceChars)
                var fullResponse = ""
                var sentenceCount = 0
                for await line in sseDelegate.lines {
                    guard let delta = OpenAIResponseParser.streamedDelta(from: line) else {
                        continue
                    }
                    for sentence in assembler.feed(delta) {
                        sentenceCount += 1
                        fullResponse += sentence + " "
                        logger.info(
                            "LLM sentence \(sentenceCount): \"\(sentence)\" (\(sentence.count) chars)"
                        )
                        continuation.yield(sentence)
                    }
                }
                if let remaining = assembler.flush() {
                    sentenceCount += 1
                    fullResponse += remaining
                    logger.info(
                        "LLM sentence \(sentenceCount) (final): \"\(remaining)\" (\(remaining.count) chars)"
                    )
                    continuation.yield(remaining)
                }
                if let failure = sseDelegate.failureDescription {
                    logger.error("OpenAI request failed: \(failure)")
                }
                if traceResponses {
                    logger.info("LLM full streaming response: \(fullResponse)")
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Request

    func makeRequest(for transcript: [LocalLLMClient.Message], stream: Bool) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            ResponseRequest(
                model: model, transcript: transcript, temperature: temperature,
                reasoningEffort: reasoningEffort, stream: stream))
        return request
    }
}

/// The Responses API body: `instructions` is the system message; the rest of the transcript
/// is `input` as role/content items.
struct ResponseRequest: Encodable {
    struct Item: Encodable {
        let role: String
        let content: String
    }
    struct Reasoning: Encodable {
        let effort: String
    }

    let model: String
    let instructions: String?
    let input: [Item]
    let temperature: Double?
    let reasoning: Reasoning?
    let stream: Bool

    init(
        model: String, transcript: [LocalLLMClient.Message], temperature: Double,
        reasoningEffort: String?, stream: Bool
    ) {
        self.model = model
        let system = transcript.filter { $0.role == .system }.map(\.content)
        self.instructions = system.isEmpty ? nil : system.joined(separator: "\n\n")
        self.input = transcript.filter { $0.role != .system }.map {
            Item(role: $0.role.rawValue, content: $0.content)
        }
        // Reasoning models refuse a temperature; send one or the other.
        self.reasoning = reasoningEffort.map(Reasoning.init(effort:))
        self.temperature = reasoningEffort == nil ? temperature : nil
        self.stream = stream
    }
}

enum OpenAIClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(code: Int, body: String)
    case missingOutputText

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI URL"
        case .invalidResponse:
            return "Invalid OpenAI response"
        case .httpError(let code, let body):
            if body.isEmpty {
                return "OpenAI API returned status \(code)"
            }
            return "OpenAI API returned status \(code): \(body)"
        case .missingOutputText:
            return "OpenAI response did not include output text"
        }
    }
}

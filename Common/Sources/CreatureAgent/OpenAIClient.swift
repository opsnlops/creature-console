import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import WorldCore

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
    /// `fast` for lower latency at a premium; nil for the default tier.
    private let serviceTier: String?
    private let minSentenceChars: Int
    /// Streaming goes through AsyncHTTPClient: on Linux, a per-request `URLSession` torn down
    /// as an HTTPS stream completes trips swift-corelibs-foundation's `_MultiHandle` retain
    /// check and aborts the process — Beaky died mid-sentence four times on 2026-09-12.
    private let streamingClient: HTTPClient?

    init(
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double,
        reasoningEffort: String? = nil,
        serviceTier: String? = nil,
        minSentenceChars: Int = 0,
        endpoint: URL = OpenAIClient.defaultEndpoint,
        streamingClient: HTTPClient? = nil,
        logger: Logger,
        traceResponses: Bool
    ) {
        self.endpoint = endpoint
        self.streamingClient = streamingClient
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
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

    /// With `tools`, the model may look things up in the world (WorldMCP) before answering;
    /// the calls it made are reported through `tools.onCall` once the answer is in.
    func respond(messages transcript: [LocalLLMClient.Message], tools: ModelTools? = nil)
        async throws -> String
    {
        logger.debug("Sending OpenAI response request (model: \(model))")
        var request = makeRequest(for: transcript, stream: false, tools: tools)
        request.timeoutInterval = tools == nil ? 60 : 90

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
        if let tools {
            for call in OpenAIResponseParser.toolCalls(from: data) {
                await tools.onCall(call)
            }
        }
        return output
    }

    /// Sentences as the model composes them, from the Responses API's SSE stream
    /// (`response.output_text.delta` events carry the text).
    func respondStreaming(messages transcript: [LocalLLMClient.Message], tools: ModelTools? = nil)
        -> AsyncStream<String>
    {
        let request = makeRequest(for: transcript, stream: true, tools: tools)
        let logger = self.logger
        let model = self.model
        let traceResponses = self.traceResponses
        let minSentenceChars = self.minSentenceChars
        let client = streamingClient
        return AsyncStream { continuation in
            Task {
                logger.debug("Starting streaming OpenAI request (model: \(model))")
                var assembler = SentenceAssembler(minimumCharacters: minSentenceChars)
                var fullResponse = ""
                var sentenceCount = 0
                func emit(_ sentence: String, final: Bool) {
                    sentenceCount += 1
                    fullResponse += sentence + " "
                    logger.info(
                        "LLM sentence \(sentenceCount)\(final ? " (final)" : ""): \"\(sentence)\" (\(sentence.count) chars)"
                    )
                    continuation.yield(sentence)
                }
                do {
                    guard let client else { throw OpenAIClientError.streamingUnavailable }
                    var streamRequest = HTTPClientRequest(url: request.url!.absoluteString)
                    streamRequest.method = .POST
                    for (name, value) in request.allHTTPHeaderFields ?? [:] {
                        streamRequest.headers.add(name: name, value: value)
                    }
                    streamRequest.body = .bytes(request.httpBody ?? Data())
                    let response = try await client.execute(streamRequest, timeout: .seconds(60))
                    guard response.status == .ok else {
                        let body = try await response.body.collect(upTo: 65_536)
                        throw OpenAIClientError.httpError(
                            code: Int(response.status.code), body: String(buffer: body))
                    }
                    var parser = ServerSentEventParser()
                    for try await buffer in response.body {
                        for frame in parser.feed(String(buffer: buffer)) {
                            // A tool the model called is reported as it completes; the
                            // words come after.
                            if let tools,
                                let call = OpenAIResponseParser.streamedToolCall(
                                    fromData: frame.data)
                            {
                                logger.info(
                                    "LLM looked it up: \(call.name)\(call.error.map { " (failed: \($0))" } ?? "")"
                                )
                                await tools.onCall(call)
                                continue
                            }
                            guard
                                let delta = OpenAIResponseParser.streamedDelta(fromData: frame.data)
                            else { continue }
                            for sentence in assembler.feed(delta) {
                                emit(sentence, final: false)
                            }
                        }
                    }
                    if let remaining = assembler.flush() {
                        emit(remaining, final: true)
                    }
                } catch {
                    logger.error("OpenAI request failed: \(error)")
                }
                if traceResponses {
                    logger.info("LLM full streaming response: \(fullResponse)")
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Request

    func makeRequest(
        for transcript: [LocalLLMClient.Message], stream: Bool, json: Bool = false,
        tools: ModelTools? = nil
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            ResponseRequest(
                model: model, transcript: transcript, temperature: temperature,
                reasoningEffort: reasoningEffort, serviceTier: serviceTier, stream: stream,
                json: json, tools: tools))
        return request
    }

    // MARK: - A JSON answer (the nightly memory job)

    /// One whole answer as a JSON object, for work that is read by code rather than spoken:
    /// the memory job asks for episodes and a reflection. Given the whole night, the request is
    /// allowed several minutes.
    func respondJSON(messages transcript: [LocalLLMClient.Message]) async throws -> Data {
        logger.debug("Sending OpenAI JSON request (model: \(model))")
        var request = makeRequest(for: transcript, stream: false, json: true)
        request.timeoutInterval = 600

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            logger.error("OpenAI request failed with status \(httpResponse.statusCode)")
            throw OpenAIClientError.httpError(code: httpResponse.statusCode, body: message)
        }
        let output = try OpenAIResponseParser.outputText(from: data)
        return Data(output.utf8)
    }
}

/// The Responses API body, in the shape April pasted from the OpenAI console (2026-09-12):
/// the system message as a `developer` item, April's and the bird's own lines as `user` /
/// `assistant` items with typed content (`input_text` in, `output_text` out), reasoning
/// effort when set, and nothing stored on OpenAI's side.
struct ResponseRequest: Encodable {
    struct Item: Encodable {
        struct Content: Encodable {
            let type: String
            let text: String
        }
        let role: String
        let content: [Content]

        init(_ message: LocalLLMClient.Message) {
            switch message.role {
            case .system:
                role = "developer"
                content = [Content(type: "input_text", text: message.content)]
            case .user:
                role = "user"
                content = [Content(type: "input_text", text: message.content)]
            case .assistant:
                role = "assistant"
                content = [Content(type: "output_text", text: message.content)]
            }
        }
    }
    struct Reasoning: Encodable {
        let effort: String
    }
    /// Plain words for speech, or a JSON object for the memory job.
    struct Text: Encodable {
        struct Format: Encodable {
            let type: String
        }
        let format: Format
        init(json: Bool) { format = Format(type: json ? "json_object" : "text") }
    }

    /// A remote MCP server the model may call on its own: WorldMCP, read only, no approvals
    /// (there is nothing to approve - every tool is a look-up).
    struct Tool: Encodable {
        let type = "mcp"
        let serverLabel: String
        let serverURL: String
        let allowedTools: [String]
        let requireApproval = "never"

        private enum CodingKeys: String, CodingKey {
            case type
            case serverLabel = "server_label"
            case serverURL = "server_url"
            case allowedTools = "allowed_tools"
            case requireApproval = "require_approval"
        }

        init(_ tools: ModelTools) {
            serverLabel = tools.serverLabel
            serverURL = tools.serverURL.absoluteString
            allowedTools = tools.allowedTools
        }
    }

    let model: String
    let input: [Item]
    let temperature: Double?
    let reasoning: Reasoning?
    let text: Text
    let serviceTier: String?
    let stream: Bool
    let store = false
    let tools: [Tool]?

    private enum CodingKeys: String, CodingKey {
        case model, input, temperature, reasoning, text, stream, store, tools
        case serviceTier = "service_tier"
    }

    init(
        model: String, transcript: [LocalLLMClient.Message], temperature: Double,
        reasoningEffort: String?, serviceTier: String? = nil, stream: Bool, json: Bool = false,
        tools: ModelTools? = nil
    ) {
        self.model = model
        self.input = transcript.map(Item.init)
        self.text = Text(json: json)
        // Reasoning models refuse a temperature; send one or the other.
        self.reasoning = reasoningEffort.map(Reasoning.init(effort:))
        self.temperature = reasoningEffort == nil ? temperature : nil
        self.serviceTier = serviceTier
        self.stream = stream
        self.tools = tools.map { [Tool($0)] }
    }
}

enum OpenAIClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(code: Int, body: String)
    case missingOutputText
    case streamingUnavailable

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
        case .streamingUnavailable:
            return "OpenAI streaming needs an HTTP client; none was configured"
        }
    }
}

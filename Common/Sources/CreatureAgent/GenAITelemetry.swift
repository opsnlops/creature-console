import Foundation
import Metrics
import Synchronization
import Tracing

/// What was said, for Honeycomb: nothing, the birds' own words, or everything a turn carried.
/// The conventions make content opt-in; April opted in to the birds' words (2026-10-15: "Yes
/// Honeycomb should get what the birds say"). `all` adds April's words, the facts of the
/// moment, and every look-up - the persona, contracts, and glossary never: they are the large
/// cached block, the same on every call.
enum GenAIContentCapture: String, Decodable, Sendable {
    case off
    case output
    case all
}

/// The OpenTelemetry GenAI semantic conventions (open-telemetry/semantic-conventions-genai,
/// Development), in one place: the names, the three spans a mind's model work makes, and the
/// metrics. Honeycomb's AI views read these names, and the spec is still moving, so nothing
/// else in the agent spells one (#230, docs/genai-semconv-plan.md).
///
/// A turn reads `invoke_agent Beaky` > `chat gpt-5.6-sol` (one per round) > `execute_tool
/// query_entity`; the agent span is the mind's, the other two the client's, joined by the
/// task-local `turn`.
enum GenAI {
    enum Key {
        static let operationName = "gen_ai.operation.name"
        static let providerName = "gen_ai.provider.name"
        static let agentName = "gen_ai.agent.name"
        static let conversationID = "gen_ai.conversation.id"
        static let outputType = "gen_ai.output.type"
        static let requestModel = "gen_ai.request.model"
        static let requestStream = "gen_ai.request.stream"
        static let requestTemperature = "gen_ai.request.temperature"
        static let requestReasoningLevel = "gen_ai.request.reasoning.level"
        static let responseID = "gen_ai.response.id"
        static let responseModel = "gen_ai.response.model"
        static let finishReasons = "gen_ai.response.finish_reasons"
        static let timeToFirstChunk = "gen_ai.response.time_to_first_chunk"
        static let inputTokens = "gen_ai.usage.input_tokens"
        static let cacheReadInputTokens = "gen_ai.usage.cache_read.input_tokens"
        static let cacheCreationInputTokens = "gen_ai.usage.cache_creation.input_tokens"
        static let outputTokens = "gen_ai.usage.output_tokens"
        static let reasoningOutputTokens = "gen_ai.usage.reasoning.output_tokens"
        static let inputMessages = "gen_ai.input.messages"
        static let outputMessages = "gen_ai.output.messages"
        static let toolName = "gen_ai.tool.name"
        static let toolCallID = "gen_ai.tool.call.id"
        static let toolType = "gen_ai.tool.type"
        static let toolCallArguments = "gen_ai.tool.call.arguments"
        static let toolCallResult = "gen_ai.tool.call.result"
        static let tokenModality = "gen_ai.token.modality"
        static let openAIAPIType = "openai.api.type"
        static let openAIRequestServiceTier = "openai.request.service_tier"
        static let openAIResponseServiceTier = "openai.response.service_tier"
        static let serverAddress = "server.address"
        static let serverPort = "server.port"
        static let errorType = "error.type"
        // Ours, beside the spec's.
        static let callKind = "creature_agent.call_kind"
        static let round = "creature_agent.round"
        static let toolsOffered = "creature_agent.tools_offered"
        static let batch = "creature_agent.batch"
        static let batchID = "creature_agent.batch.id"
    }

    enum Metric {
        static let inputTokens = "gen_ai.client.inference.usage.input_tokens"
        static let cacheReadInputTokens = "gen_ai.client.inference.usage.cache_read.input_tokens"
        static let cacheCreationInputTokens =
            "gen_ai.client.inference.usage.cache_creation.input_tokens"
        static let outputTokens = "gen_ai.client.inference.usage.output_tokens"
        static let reasoningOutputTokens = "gen_ai.client.inference.usage.reasoning.output_tokens"
        static let inferenceDuration = "gen_ai.client.inference.duration"
        static let timeToFirstChunk = "gen_ai.client.inference.time_to_first_chunk"
        static let invokeAgentDuration = "gen_ai.invoke_agent.duration"
        static let executeToolDuration = "gen_ai.execute_tool.duration"
    }

    static let provider = "openai"

    /// The spec's bucket bounds, in seconds, for each duration histogram: handed to the OTel
    /// bootstrap, which would otherwise use its own millisecond-shaped defaults.
    static let durationHistogramBuckets: [String: [Duration]] = {
        let inference = [
            0.01, 0.02, 0.04, 0.08, 0.16, 0.32, 0.64, 1.28, 2.56, 5.12, 10.24,
            20.48, 40.96, 81.92,
        ]
        let agent = [0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8, 25.6, 51.2, 102.4, 204.8, 409.6]
        func seconds(_ bounds: [Double]) -> [Duration] {
            bounds.map { Duration.nanoseconds(Int64(($0 * 1e9).rounded())) }
        }
        return [
            Metric.inferenceDuration: seconds(inference),
            Metric.timeToFirstChunk: seconds(inference),
            Metric.executeToolDuration: seconds(inference),
            Metric.invokeAgentDuration: seconds(agent),
        ]
    }()

    // MARK: - The turn

    /// Who is thinking, in which conversation, on what kind of call: set by the mind around
    /// its model work, read by the client that sees the provider's answers. A child task
    /// inherits it; the streaming client's task is one.
    struct Turn: Sendable {
        var agentName: String
        var conversationID: String?
        var kind: LLMCallKind
        var capture: GenAIContentCapture
        let tally = Tally()
    }

    @TaskLocal static var turn: Turn?

    /// The `execute_tool` span a look-up is running under, so an MCP client can describe its
    /// call on it rather than making a second span for the same thing (the MCP conventions:
    /// "SHOULD add MCP-specific attributes to the existing tool execution span").
    @TaskLocal static var toolSpan: (any Span)?

    /// What the rounds of a turn add up to, for the agent span.
    final class Tally: Sendable {
        struct Totals: Equatable {
            var inputTokens = 0
            var outputTokens = 0
            var finishReasons: [String] = []
        }
        private let totals = Mutex(Totals())

        func add(_ usage: LLMUsage?, finishReason: String?) {
            totals.withLock { totals in
                totals.inputTokens += usage?.inputTokens ?? 0
                totals.outputTokens += usage?.outputTokens ?? 0
                if let finishReason { totals.finishReasons = [finishReason] }
            }
        }

        var current: Totals { totals.withLock { $0 } }
    }

    // MARK: - invoke_agent

    /// The mind's model work for one turn, a question, or a night's memory: `invoke_agent
    /// {name}`, INTERNAL. The rounds' usage is summed onto it when the work is done.
    static func invokeAgent<T>(
        _ name: String, conversationID: String?, kind: LLMCallKind,
        capture: GenAIContentCapture, model: String, outputType: String = "text",
        _ operation: (any Span) async throws -> T
    ) async throws -> T {
        let turn = Turn(
            agentName: name, conversationID: conversationID, kind: kind, capture: capture)
        let started = ContinuousClock.now
        return try await withSpan("invoke_agent \(name)", ofKind: .internal) { span in
            span.attributes[Key.operationName] = "invoke_agent"
            span.attributes[Key.agentName] = name
            span.attributes[Key.conversationID] = conversationID
            span.attributes[Key.outputType] = outputType
            span.attributes[Key.requestModel] = model
            span.attributes[Key.callKind] = kind.rawValue
            var failure: String?
            defer {
                let totals = turn.tally.current
                span.attributes[Key.inputTokens] = totals.inputTokens
                span.attributes[Key.outputTokens] = totals.outputTokens
                if !totals.finishReasons.isEmpty {
                    span.attributes[Key.finishReasons] = totals.finishReasons
                }
                span.attributes[Key.errorType] = failure
                Timer(
                    label: Metric.invokeAgentDuration,
                    dimensions: dimensions(
                        [
                            ("gen_ai.operation.name", "invoke_agent"), ("gen_ai.agent.name", name),
                            ("gen_ai.request.model", model), (Key.callKind, kind.rawValue),
                        ],
                        unit: "s", error: failure)
                ).record(duration: ContinuousClock.now - started)
            }
            do {
                return try await $turn.withValue(turn) { try await operation(span) }
            } catch {
                failure = errorType(of: error)
                throw error
            }
        }
    }

    // MARK: - chat

    /// One round's request, as the conventions describe it.
    struct Request: Sendable {
        var model: String
        var stream = false
        var json = false
        var temperature: Double? = nil
        var reasoningEffort: String? = nil
        var serviceTier: String? = nil
        var endpoint: URL = OpenAIClient.defaultEndpoint
        var round = 0
        var toolsOffered = 0
        var batchID: String? = nil
    }

    /// The span of one round, handed to the client while it reads the answer.
    final class Inference: Sendable {
        let span: any Span
        private let started: ContinuousClock.Instant
        private let firstChunk = Mutex<Duration?>(nil)
        private let reported = Mutex<LLMUsage?>(nil)

        init(span: any Span, started: ContinuousClock.Instant) {
            self.span = span
            self.started = started
        }

        /// The stream's first chunk arrived: once, measured from the request.
        func receivedFirstChunk() {
            let elapsed = ContinuousClock.now - started
            let recorded = firstChunk.withLock { held -> Bool in
                guard held == nil else { return false }
                held = elapsed
                return true
            }
            if recorded { span.attributes[Key.timeToFirstChunk] = elapsed.seconds }
        }

        var timeToFirstChunk: Duration? { firstChunk.withLock { $0 } }
        var usage: LLMUsage? { reported.withLock { $0 } }

        /// What the provider said about its answer, and - when capture allows - the answer
        /// itself: the words, and any look-ups it asked for.
        func finished(
            _ summary: OpenAIResponseSummary?, text: String,
            calls: [OpenAIResponseParser.FunctionCall]
        ) {
            let reason = summary?.finishReason(askedForTools: !calls.isEmpty) ?? "error"
            span.attributes[Key.finishReasons] = [reason]
            if let summary {
                span.attributes[Key.responseID] = summary.id
                span.attributes[Key.responseModel] = summary.model
                span.attributes[Key.openAIResponseServiceTier] = summary.serviceTier
                if let usage = summary.usage {
                    GenAI.record(usage, on: span)
                    reported.withLock { $0 = usage }
                }
            }
            GenAI.turn?.tally.add(summary?.usage, finishReason: reason)
            if let capture = GenAI.turn?.capture, capture != .off {
                span.attributes[Key.outputMessages] = GenAIMessages.output(
                    text: text, calls: calls, finishReason: reason)
            }
        }
    }

    /// One round with the model: `chat {model}`, CLIENT. The required attributes are set at
    /// the start, where a sampler would look; usage, the answer, and the metrics at the end -
    /// a failed round counts too, with no tokens and its `error.type`.
    static func inference<T>(
        _ request: Request, input: @autoclosure () -> String? = nil,
        _ operation: (Inference) async throws -> T
    ) async throws -> T {
        let turn = Self.turn
        let started = ContinuousClock.now
        return try await withSpan("chat \(request.model)", ofKind: .client) { span in
            span.attributes[Key.operationName] = "chat"
            span.attributes[Key.providerName] = provider
            span.attributes[Key.requestModel] = request.model
            span.attributes[Key.openAIAPIType] = "responses"
            span.attributes[Key.serverAddress] = request.endpoint.host
            span.attributes[Key.serverPort] = request.endpoint.port ?? 443
            if request.stream { span.attributes[Key.requestStream] = true }
            if request.json { span.attributes[Key.outputType] = "json" }
            span.attributes[Key.requestTemperature] = request.temperature
            span.attributes[Key.requestReasoningLevel] = request.reasoningEffort
            if let tier = request.serviceTier, tier != "auto" {
                span.attributes[Key.openAIRequestServiceTier] = tier
            }
            span.attributes[Key.agentName] = turn?.agentName
            span.attributes[Key.conversationID] = turn?.conversationID
            span.attributes[Key.callKind] = turn?.kind.rawValue
            span.attributes[Key.round] = request.round
            span.attributes[Key.toolsOffered] = request.toolsOffered
            if let batchID = request.batchID {
                span.attributes[Key.batch] = true
                span.attributes[Key.batchID] = batchID
            }
            if turn?.capture == .all, let input = input() {
                span.attributes[Key.inputMessages] = input
            }
            let inference = Inference(span: span, started: started)
            var failure: String?
            defer {
                let elapsed = ContinuousClock.now - started
                recordInference(
                    request, kind: turn?.kind, usage: inference.usage, elapsed: elapsed,
                    firstChunk: inference.timeToFirstChunk, error: failure)
            }
            do {
                return try await operation(inference)
            } catch {
                failure = errorType(of: error)
                span.attributes[Key.errorType] = failure
                span.attributes[Key.finishReasons] = ["error"]
                turn?.tally.add(nil, finishReason: "error")
                throw error
            }
        }
    }

    /// Usage on a span, by the conventions' names. Input includes the cached part, as the
    /// provider reports it; reasoning is part of the output.
    static func record(_ usage: LLMUsage, on span: any Span) {
        span.attributes[Key.inputTokens] = usage.inputTokens
        span.attributes[Key.cacheReadInputTokens] = usage.cachedTokens
        span.attributes[Key.cacheCreationInputTokens] = usage.cacheWriteTokens
        span.attributes[Key.outputTokens] = usage.outputTokens
        span.attributes[Key.reasoningOutputTokens] = usage.reasoningTokens
    }

    private static func recordInference(
        _ request: Request, kind: LLMCallKind?, usage: LLMUsage?, elapsed: Duration,
        firstChunk: Duration?, error: String?
    ) {
        let base: [(String, String)] = [
            ("gen_ai.operation.name", "chat"), ("gen_ai.provider.name", provider),
            ("gen_ai.request.model", request.model),
            (Key.callKind, kind?.rawValue ?? "unknown"),
        ]
        // Every round counts, a failed one with no tokens: the spec asks for the zero.
        for (label, count) in [
            (Metric.inputTokens, usage?.inputTokens ?? 0),
            (Metric.cacheReadInputTokens, usage?.cachedTokens ?? 0),
            (Metric.cacheCreationInputTokens, usage?.cacheWriteTokens ?? 0),
            (Metric.outputTokens, usage?.outputTokens ?? 0),
            (Metric.reasoningOutputTokens, usage?.reasoningTokens ?? 0),
        ] {
            Counter(
                label: label,
                dimensions: dimensions(
                    base + [(Key.tokenModality, "text")], unit: "{token}", error: error)
            ).increment(by: count)
        }
        // A batch's answer was hours in the making at the provider; its "duration" here is
        // reading a file, and would only mislead the histogram.
        guard request.batchID == nil else { return }
        Timer(
            label: Metric.inferenceDuration, dimensions: dimensions(base, unit: "s", error: error)
        )
        .record(duration: elapsed)
        if request.stream, let firstChunk {
            Timer(
                label: Metric.timeToFirstChunk, dimensions: dimensions(base, unit: "s", error: nil)
            ).record(duration: firstChunk)
        }
    }

    // MARK: - execute_tool

    /// A look-up the model asked for, run by the mind: `execute_tool {name}`, INTERNAL. The
    /// arguments and the result ride along only when capture is `all` - a look-up answers
    /// with the world's facts.
    static func executeTool(
        _ name: String, callID: String, arguments: String,
        _ operation: () async throws -> String
    ) async throws -> String {
        let turn = Self.turn
        let started = ContinuousClock.now
        return try await withSpan("execute_tool \(name)", ofKind: .internal) { span in
            span.attributes[Key.operationName] = "execute_tool"
            span.attributes[Key.toolName] = name
            span.attributes[Key.toolCallID] = callID
            span.attributes[Key.toolType] = "function"
            span.attributes[Key.agentName] = turn?.agentName
            span.attributes[Key.conversationID] = turn?.conversationID
            let everything = turn?.capture == .all
            if everything { span.attributes[Key.toolCallArguments] = arguments }
            var failure: String?
            defer {
                Timer(
                    label: Metric.executeToolDuration,
                    dimensions: dimensions(
                        [("gen_ai.operation.name", "execute_tool"), ("gen_ai.tool.name", name)],
                        unit: "s", error: failure)
                ).record(duration: ContinuousClock.now - started)
            }
            do {
                let result = try await $toolSpan.withValue(span) { try await operation() }
                if everything { span.attributes[Key.toolCallResult] = result }
                return result
            } catch {
                failure = errorType(of: error)
                span.attributes[Key.errorType] = failure
                throw error
            }
        }
    }

    // MARK: - Helpers

    /// A low-cardinality name for what went wrong: the HTTP status, or the error's kind.
    static func errorType(of error: any Error) -> String {
        switch error {
        case OpenAIClientError.httpError(let code, _): "\(code)"
        case let error as OpenAIClientError: "\(error)".components(separatedBy: "(")[0]
        // WorldMCP's own words for it: `tool_error`, the JSON-RPC code, the HTTP status.
        case let failure as WorldMCPClient.Failure: failure.kind
        case is CancellationError: "cancelled"
        default: String(describing: type(of: error))
        }
    }

    private static func dimensions(
        _ attributes: [(String, String)], unit: String, error: String?
    ) -> [(String, String)] {
        var dimensions = [("unit", unit)] + attributes
        if let error { dimensions.append(("error.type", error)) }
        return dimensions
    }
}

/// What was said, in the conventions' message shape (`gen-ai-input-messages.json`,
/// `gen-ai-output-messages.json`), serialized: a span attribute in Swift is a string.
enum GenAIMessages {
    private struct Message: Encodable {
        var role: String
        var parts: [Part]
        /// Deprecated in the spec's next release for `gen_ai.response.finish_reasons`, but
        /// required by the release Honeycomb reads (1.41).
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case role, parts
            case finishReason = "finish_reason"
        }
    }

    private struct Part: Encodable {
        var type: String
        var content: String? = nil
        var id: String? = nil
        var name: String? = nil
        var arguments: String? = nil
        var response: String? = nil
    }

    /// The model's answer: its words, then any look-ups it asked for.
    static func output(
        text: String, calls: [OpenAIResponseParser.FunctionCall], finishReason: String
    ) -> String {
        var parts: [Part] = []
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { parts.append(Part(type: "text", content: words)) }
        parts += calls.map {
            Part(type: "tool_call", id: $0.callID, name: $0.name, arguments: $0.arguments)
        }
        return encoded([Message(role: "assistant", parts: parts, finishReason: finishReason)])
    }

    /// What the model was handed, but for the system message - the persona, contracts, and
    /// glossary, the same on every call: the turns, the facts of the moment, and the
    /// look-ups of earlier rounds.
    static func input(
        _ transcript: [LocalLLMClient.Message], extra: [ResponseRequest.Item] = []
    ) -> String {
        var messages: [Message] = transcript.compactMap { message in
            switch message.role {
            case .system: nil
            case .user: Message(role: "user", parts: [Part(type: "text", content: message.content)])
            case .assistant:
                Message(role: "assistant", parts: [Part(type: "text", content: message.content)])
            }
        }
        for item in extra {
            switch item {
            case .message(let role, let content):
                messages.append(
                    Message(
                        role: role == "developer" ? "user" : role,
                        parts: content.map { Part(type: "text", content: $0.text) }))
            case .functionCall(let call):
                messages.append(
                    Message(
                        role: "assistant",
                        parts: [
                            Part(
                                type: "tool_call", id: call.callID, name: call.name,
                                arguments: call.arguments)
                        ]))
            case .functionCallOutput(let callID, let output):
                messages.append(
                    Message(
                        role: "tool",
                        parts: [Part(type: "tool_call_response", id: callID, response: output)]))
            }
        }
        return encoded(messages)
    }

    private static func encoded(_ messages: [Message]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(messages) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Duration {
    /// Seconds, as a double: what the conventions measure time in.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

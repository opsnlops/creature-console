import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import InMemoryTracing
import Logging
import NIOCore
import Observability
import TestTracing
import Testing
import Tracing
import WorldCore

@testable import creature_agent

/// The process's one tracer, shared with every test target (#249): every test here finds its own
/// spans by its own conversation id, so tests running side by side never read each other's.
private var tracer: InMemoryTracer { testTracer }

private func spans(in conversation: String) -> [FinishedInMemorySpan] {
    tracer.finishedSpans.filter {
        $0.attributes.get(GenAI.Key.conversationID) == .string(conversation)
    }
}

@Suite("GenAI semantic conventions")
struct GenAITelemetryTests {
    /// The tracer is bootstrapped before a test does anything, not when it first reads.
    init() { _ = tracer }

    private let transcript = [
        LocalLLMClient.Message(role: .system, content: "You are Beaky."),
        LocalLLMClient.Message(role: .user, content: "April: who is Jesse?"),
    ]

    /// A Responses API stream: round 0 asks to look Jesse up, round 1 answers - each closing
    /// with the response's id, model, tier, and usage, the way the provider sends them.
    private func responder(rounds: Rounds) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        router.post("v1/responses") { _, _ in
            let round = await rounds.next()
            var events = "event: response.created\ndata: {\"type\":\"response.created\"}\n\n"
            if round == 0 {
                events +=
                    "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"call_id\":\"call_9\",\"name\":\"query_entity\",\"arguments\":\"{\\\"entity_id\\\":\\\"person:jesse\\\"}\"}}\n\n"
            } else {
                for delta in ["Jesse is your contractor, April. ", "He was here Sunday."] {
                    events +=
                        "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"\(delta)\"}\n\n"
                }
            }
            events +=
                "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_\(round)\",\"model\":\"gpt-6-astra-2026-10-01\",\"status\":\"completed\",\"service_tier\":\"default\",\"usage\":{\"input_tokens\":100,\"output_tokens\":20,\"input_tokens_details\":{\"cached_tokens\":80},\"output_tokens_details\":{\"reasoning_tokens\":5}}}}\n\n"
            return Response(
                status: .ok, headers: [.contentType: "text/event-stream"],
                body: .init(byteBuffer: ByteBuffer(string: events)))
        }
        return router
    }

    /// One bird's turn against the fake provider, inside its `invoke_agent` span.
    private func turn(
        conversation: String, capture: GenAIContentCapture, failing: Bool = false
    ) async throws -> [String] {
        let rounds = Rounds()
        let router: Router<BasicRequestContext>
        if failing {
            router = Router(context: BasicRequestContext.self)
            router.post("v1/responses") { _, _ in
                Response(
                    status: .tooManyRequests,
                    body: .init(byteBuffer: ByteBuffer(string: "slow down")))
            }
        } else {
            router = responder(rounds: rounds)
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let transcript = self.transcript
        return try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await httpClient.shutdown() } }
            let client = OpenAIClient(
                apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "You are Beaky.",
                temperature: 1, reasoningEffort: "low", serviceTier: "priority",
                endpoint: URL(string: "http://localhost:\(port)/v1/responses")!,
                streamingClient: httpClient,
                logger: Logger(label: "genai-tests"), traceResponses: false)
            let tools = ModelTools(
                serverLabel: "world",
                catalogue: {
                    [
                        WorldMCPClient.ToolDefinition(
                            name: "query_entity", description: "", inputSchema: .object([:]))
                    ]
                },
                call: { _, _ in
                    #"{"facts":[{"predicate":"person.relationship","value":"contractor"}]}"#
                },
                onCall: { _ in })
            return try await GenAI.invokeAgent(
                "Beaky", conversationID: conversation, kind: .scene, capture: capture,
                model: "gpt-6-astra"
            ) { _ in
                var sentences: [String] = []
                for await sentence in client.respondStreaming(messages: transcript, tools: tools) {
                    sentences.append(sentence)
                }
                return sentences
            }
        }
    }

    @Test("A turn reads invoke_agent > chat > execute_tool > chat, each named by the spec")
    func spanTree() async throws {
        let conversation = "scene:tree-\(UUID().uuidString)"
        let sentences = try await turn(conversation: conversation, capture: .output)
        #expect(sentences == ["Jesse is your contractor, April.", "He was here Sunday."])

        let found = spans(in: conversation)
        let agent = try #require(found.first { $0.operationName == "invoke_agent Beaky" })
        let chats = found.filter { $0.operationName == "chat gpt-6-astra" }
        let tool = try #require(found.first { $0.operationName == "execute_tool query_entity" })
        #expect(chats.count == 2)

        // The tree: both rounds and the look-up are the agent's children.
        #expect(agent.kind == .internal)
        #expect(chats.allSatisfy { $0.parentSpanID == agent.spanID && $0.kind == .client })
        #expect(tool.parentSpanID == agent.spanID && tool.kind == .internal)

        // The agent span: who, where, and the rounds summed.
        #expect(agent.attributes.get(GenAI.Key.operationName) == .string("invoke_agent"))
        #expect(agent.attributes.get(GenAI.Key.agentName) == .string("Beaky"))
        #expect(agent.attributes.get(GenAI.Key.callKind) == .string("scene"))
        #expect(agent.attributes.get(GenAI.Key.inputTokens) == .int64(200))
        #expect(agent.attributes.get(GenAI.Key.outputTokens) == .int64(40))
        #expect(agent.attributes.get(GenAI.Key.finishReasons) == .stringArray(["stop"]))

        // Each round: the required attributes, the request's knobs, the answer, its cost.
        for chat in chats {
            #expect(chat.attributes.get(GenAI.Key.operationName) == .string("chat"))
            #expect(chat.attributes.get(GenAI.Key.providerName) == .string("openai"))
            #expect(chat.attributes.get(GenAI.Key.requestModel) == .string("gpt-6-astra"))
            #expect(chat.attributes.get(GenAI.Key.openAIAPIType) == .string("responses"))
            #expect(chat.attributes.get(GenAI.Key.requestStream) == .bool(true))
            #expect(chat.attributes.get(GenAI.Key.requestReasoningLevel) == .string("low"))
            #expect(chat.attributes.get(GenAI.Key.requestTemperature) == nil)
            #expect(
                chat.attributes.get(GenAI.Key.openAIRequestServiceTier) == .string("priority"))
            #expect(
                chat.attributes.get(GenAI.Key.openAIResponseServiceTier) == .string("default"))
            #expect(
                chat.attributes.get(GenAI.Key.responseModel)
                    == .string("gpt-6-astra-2026-10-01"))
            #expect(chat.attributes.get(GenAI.Key.agentName) == .string("Beaky"))
            #expect(chat.attributes.get(GenAI.Key.inputTokens) == .int64(100))
            #expect(chat.attributes.get(GenAI.Key.cacheReadInputTokens) == .int64(80))
            #expect(chat.attributes.get(GenAI.Key.outputTokens) == .int64(20))
            #expect(chat.attributes.get(GenAI.Key.reasoningOutputTokens) == .int64(5))
            #expect(chat.attributes.get(GenAI.Key.serverAddress) == .string("localhost"))
            if case .double(let seconds)? = chat.attributes.get(GenAI.Key.timeToFirstChunk) {
                #expect(seconds >= 0)
            } else {
                Issue.record("no time to first chunk")
            }
            // `output` capture: the answer, never what the model was handed.
            #expect(chat.attributes.get(GenAI.Key.inputMessages) == nil)
        }
        let asking = try #require(chats.first { $0.attributes.get(GenAI.Key.round) == .int64(0) })
        let answering = try #require(
            chats.first { $0.attributes.get(GenAI.Key.round) == .int64(1) })
        #expect(asking.attributes.get(GenAI.Key.responseID) == .string("resp_0"))
        #expect(asking.attributes.get(GenAI.Key.finishReasons) == .stringArray(["tool_calls"]))
        #expect(answering.attributes.get(GenAI.Key.finishReasons) == .stringArray(["stop"]))
        guard case .string(let said)? = answering.attributes.get(GenAI.Key.outputMessages) else {
            Issue.record("no output messages")
            return
        }
        let messages = try JSONSerialization.jsonObject(with: Data(said.utf8)) as? [[String: Any]]
        let parts = messages?.first?["parts"] as? [[String: Any]]
        #expect(messages?.first?["role"] as? String == "assistant")
        #expect(parts?.first?["type"] as? String == "text")
        #expect(
            parts?.first?["content"] as? String
                == "Jesse is your contractor, April. He was here Sunday.")
        guard case .string(let asked)? = asking.attributes.get(GenAI.Key.outputMessages) else {
            Issue.record("no output messages on the asking round")
            return
        }
        #expect(asked.contains(#""type":"tool_call""#) && asked.contains("query_entity"))

        // The look-up: named, its call id, and - at `output` - not what it found.
        #expect(tool.attributes.get(GenAI.Key.toolName) == .string("query_entity"))
        #expect(tool.attributes.get(GenAI.Key.toolCallID) == .string("call_9"))
        #expect(tool.attributes.get(GenAI.Key.toolType) == .string("function"))
        #expect(tool.attributes.get(GenAI.Key.toolCallArguments) == nil)
        #expect(tool.attributes.get(GenAI.Key.toolCallResult) == nil)
    }

    @Test("`all` adds what the model was handed - never the system message - and the look-ups")
    func captureAll() async throws {
        let conversation = "scene:all-\(UUID().uuidString)"
        _ = try await turn(conversation: conversation, capture: .all)
        let found = spans(in: conversation)
        let answering = try #require(
            found.first {
                $0.operationName == "chat gpt-6-astra"
                    && $0.attributes.get(GenAI.Key.round) == .int64(1)
            })
        guard case .string(let input)? = answering.attributes.get(GenAI.Key.inputMessages) else {
            Issue.record("no input messages")
            return
        }
        #expect(input.contains("April: who is Jesse?"))
        #expect(!input.contains("You are Beaky."))
        #expect(input.contains(#""type":"tool_call_response""#))
        let tool = try #require(found.first { $0.operationName == "execute_tool query_entity" })
        #expect(tool.attributes.get(GenAI.Key.toolCallArguments) != nil)
        #expect(
            tool.attributes.get(GenAI.Key.toolCallResult).map { "\($0)".contains("contractor") }
                == true)
    }

    @Test("`off` writes no words at all")
    func captureOff() async throws {
        let conversation = "scene:off-\(UUID().uuidString)"
        _ = try await turn(conversation: conversation, capture: .off)
        let found = spans(in: conversation)
        #expect(!found.isEmpty)
        for span in found {
            #expect(span.attributes.get(GenAI.Key.outputMessages) == nil)
            #expect(span.attributes.get(GenAI.Key.inputMessages) == nil)
        }
    }

    @Test("A refused round says why: error.type is the status, the finish reason `error`")
    func failedRound() async throws {
        let conversation = "scene:failed-\(UUID().uuidString)"
        // The streaming client logs and ends the stream; the round's span keeps the failure.
        let sentences = try await turn(conversation: conversation, capture: .output, failing: true)
        #expect(sentences.isEmpty)
        let found = spans(in: conversation)
        let chat = try #require(found.first { $0.operationName == "chat gpt-6-astra" })
        #expect(chat.attributes.get(GenAI.Key.errorType) == .string("429"))
        #expect(chat.attributes.get(GenAI.Key.finishReasons) == .stringArray(["error"]))
        let agent = try #require(found.first { $0.operationName == "invoke_agent Beaky" })
        #expect(agent.attributes.get(GenAI.Key.finishReasons) == .stringArray(["error"]))
    }

    @Test("A batch's answer is a chat span marked as one, with its cost and the batch named")
    func batchAnswer() async throws {
        let conversation = "memory:batch-\(UUID().uuidString)"
        let client = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "", temperature: 1,
            logger: Logger(label: "genai-tests"), traceResponses: false)
        let body = Data(
            #"{"id":"resp_b","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"episodes\":[]}"}]}],"usage":{"input_tokens":9000,"output_tokens":700,"input_tokens_details":{"cached_tokens":0}}}"#
                .utf8)
        let answer = try await GenAI.invokeAgent(
            "Beaky", conversationID: conversation, kind: .memory, capture: .off,
            model: "gpt-6-astra", outputType: "json"
        ) { _ in try await client.jsonAnswer(fromBatch: body, batchID: "batch_42") }
        #expect(String(decoding: answer, as: UTF8.self) == #"{"episodes":[]}"#)
        let found = spans(in: conversation)
        let chat = try #require(found.first { $0.operationName == "chat gpt-6-astra" })
        #expect(chat.attributes.get(GenAI.Key.batch) == .bool(true))
        #expect(chat.attributes.get(GenAI.Key.batchID) == .string("batch_42"))
        #expect(chat.attributes.get(GenAI.Key.outputType) == .string("json"))
        #expect(chat.attributes.get(GenAI.Key.inputTokens) == .int64(9000))
        #expect(chat.attributes.get(GenAI.Key.callKind) == .string("memory"))
        let agent = try #require(found.first { $0.operationName == "invoke_agent Beaky" })
        #expect(agent.attributes.get(GenAI.Key.outputType) == .string("json"))
    }

    @Test("A bird's scene turn is invoke_agent {bird}, in the scene's conversation")
    func sceneTurnIsTheScene() async throws {
        let now = Date(timeIntervalSince1970: 1_789_600_000)
        let beaky = try EntityID(validating: "character:beaky")
        let april = try EntityID(validating: "person:april")
        let sceneID = try SceneID(validating: "scene:genai-\(UUID().uuidString.lowercased())")
        var configuration = CharacterMind.Configuration(
            persona: .text("You are Beaky."), characterID: beaky, personID: april,
            maximumReplyAge: 3_600, maximumContextTurns: 20, modelTimeout: .seconds(5),
            modelName: "gpt-6-astra")
        configuration.contentCapture = .output
        let mind = CharacterMind(
            configuration: configuration, respond: { _, _ in "Hello, April." },
            logger: Logger(label: "genai-tests"))
        let offer = try SceneTurnOffer(
            sceneID: sceneID, characterID: beaky,
            responseID: ResponseID(validating: "response:genai"),
            deadline: now.addingTimeInterval(8),
            trigger: SceneTrigger(
                kind: .personUtterance, eventID: .generated(), speakerID: april,
                text: "Hello, birds."),
            participants: [beaky], turns: [])
        let envelope = try WorldEventEnvelope(
            occurredAt: now,
            source: EventSource(id: SourceID(validating: "world:scenes"), kind: "world"),
            subjectIDs: [beaky], epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: offer)
        _ = try await mind.consider(
            WorldSceneConsideration(worldSequence: 1, envelope: envelope, offer: offer), now: now)

        let agent = try #require(
            spans(in: sceneID.rawValue).first { $0.operationName == "invoke_agent Beaky" })
        #expect(agent.attributes.get(GenAI.Key.callKind) == .string("scene"))
        #expect(agent.attributes.get(GenAI.Key.requestModel) == .string("gpt-6-astra"))
        // Never the house's one conversation, which would make months one row.
        #expect(
            tracer.finishedSpans.allSatisfy {
                $0.attributes.get(GenAI.Key.conversationID) != .string("conversation:april-house")
            })
    }

    /// A WorldMCP that answers `tools/list` and `tools/call` - or, for `refuse`, says the
    /// tool failed (`isError`).
    private func mcpServer(refuse: Bool = false) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        router.post("world/mcp") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            let asked = try WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: body)
            let result: WorldJSONValue =
                asked["method"] == .string("tools/list")
                ? .object(["tools": .array([.object(["name": .string("query_entity")])])])
                : .object([
                    "content": .array([
                        .object(["type": .string("text"), "text": .string("Jesse: contractor")])
                    ]),
                    "isError": .bool(refuse),
                ])
            return Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: .init(
                    byteBuffer: ByteBuffer(
                        bytes: try WorldJSON.makeEncoder().encode(
                            WorldJSONValue.object(["jsonrpc": .string("2.0"), "result": result])))))
        }
        return router
    }

    @Test("A look-up's MCP call is described on its execute_tool span, never a second span")
    func mcpOnTheToolSpan() async throws {
        let conversation = "scene:mcp-\(UUID().uuidString)"
        let application = Application(
            router: mcpServer(), configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let port = try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await httpClient.shutdown() } }
            let mcp = WorldMCPClient(
                url: URL(string: "http://localhost:\(port)/world/mcp")!, client: httpClient,
                logger: Logger(label: "genai-tests"))
            #expect(try await mcp.listTools().map(\.name) == ["query_entity"])
            try await GenAI.invokeAgent(
                "Beaky", conversationID: conversation, kind: .scene, capture: .off,
                model: "gpt-6-astra"
            ) { _ in
                let answer = try await GenAI.executeTool(
                    "query_entity", callID: "call_1", arguments: "{}"
                ) {
                    try await mcp.call("query_entity", arguments: "{}")
                }
                #expect(answer == "Jesse: contractor")
            }
            return port
        }
        let found = spans(in: conversation)
        let tool = try #require(found.first { $0.operationName == "execute_tool query_entity" })
        #expect(tool.attributes.get(MCPTelemetry.Key.methodName) == .string("tools/call"))
        #expect(tool.attributes.get(MCPTelemetry.Key.jsonRPCRequestID) == .string("1"))
        #expect(tool.attributes.get(MCPTelemetry.Key.serverPort) == .int64(Int64(port)))
        #expect(tool.attributes.get(MCPTelemetry.Key.networkTransport) == .string("tcp"))
        // One span for one call: no `tools/call query_entity` beside the tool's.
        #expect(
            !tracer.finishedSpans.contains {
                $0.operationName == "tools/call query_entity"
                    && $0.attributes.get(MCPTelemetry.Key.serverPort) == .int64(Int64(port))
            })
        // Asking for the catalogue is no tool's: it gets a CLIENT span of its own.
        let listed = try #require(
            tracer.finishedSpans.first {
                $0.operationName == "tools/list"
                    && $0.attributes.get(MCPTelemetry.Key.serverPort) == .int64(Int64(port))
            })
        #expect(listed.kind == .client)
        #expect(listed.attributes.get(MCPTelemetry.Key.methodName) == .string("tools/list"))
    }

    @Test("A tool that answers isError is a tool_error on its span")
    func mcpToolError() async throws {
        let conversation = "scene:mcp-error-\(UUID().uuidString)"
        let application = Application(
            router: mcpServer(refuse: true),
            configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await httpClient.shutdown() } }
            let mcp = WorldMCPClient(
                url: URL(string: "http://localhost:\(port)/world/mcp")!, client: httpClient,
                logger: Logger(label: "genai-tests"))
            try await GenAI.invokeAgent(
                "Beaky", conversationID: conversation, kind: .scene, capture: .off,
                model: "gpt-6-astra"
            ) { _ in
                await #expect(throws: WorldMCPClient.Failure.self) {
                    try await GenAI.executeTool("query_entity", callID: "call_2", arguments: "{}") {
                        try await mcp.call("query_entity", arguments: "{}")
                    }
                }
            }
        }
        let tool = try #require(
            spans(in: conversation).first { $0.operationName == "execute_tool query_entity" })
        #expect(tool.attributes.get(MCPTelemetry.Key.errorType) == .string("tool_error"))
    }

    @Test("The trace rides in params._meta beside what was there; only the W3C keys")
    func traceInMeta() {
        let params: WorldJSONValue = .object([
            "name": .string("query_entity"),
            "_meta": .object(["audience": .string("minds")]),
        ])
        let carried = WorldMCPClient.carryingTheTrace(
            params,
            headers: [
                "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
                "tracestate": "rojo=00f067aa0ba902b7", "in-memory-trace-id": "x",
            ])
        #expect(carried["_meta"]?["audience"] == .string("minds"))
        #expect(
            carried["_meta"]?["traceparent"]
                == .string("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"))
        #expect(carried["_meta"]?["tracestate"] == .string("rojo=00f067aa0ba902b7"))
        #expect(carried["_meta"]?["in-memory-trace-id"] == nil)
        #expect(carried["name"] == .string("query_entity"))
        // Outside a trace, the params go as they came.
        #expect(WorldMCPClient.carryingTheTrace(params, headers: [:]) == params)
    }

    @Test("Finish reasons follow the Responses API's status")
    func finishReasons() {
        let done = OpenAIResponseSummary(status: "completed")
        #expect(done.finishReason(askedForTools: false) == "stop")
        #expect(done.finishReason(askedForTools: true) == "tool_calls")
        #expect(
            OpenAIResponseSummary(status: "incomplete", incompleteReason: "max_output_tokens")
                .finishReason(askedForTools: false) == "max_output_tokens")
        #expect(
            OpenAIResponseSummary(status: "failed").finishReason(askedForTools: false) == "error")
    }

    @Test("Reasoning tokens are read from the usage's output details")
    func reasoningTokens() throws {
        let whole = Data(
            #"{"output":[],"usage":{"input_tokens":10,"output_tokens":8,"output_tokens_details":{"reasoning_tokens":6}}}"#
                .utf8)
        #expect(OpenAIResponseParser.usage(from: whole)?.reasoningTokens == 6)
    }

    @Test("Error types stay low-cardinality")
    func errorTypes() {
        #expect(GenAI.errorType(of: OpenAIClientError.httpError(code: 500, body: "x")) == "500")
        #expect(GenAI.errorType(of: OpenAIClientError.missingOutputText) == "missingOutputText")
        #expect(GenAI.errorType(of: CancellationError()) == "cancelled")
    }

    @Test("The spec's duration buckets, in seconds, for every GenAI histogram")
    func histogramBuckets() {
        let inference = GenAI.durationHistogramBuckets[GenAI.Metric.inferenceDuration]
        #expect(inference?.first == .milliseconds(10))
        #expect(inference?.last == .milliseconds(81_920))
        #expect(
            GenAI.durationHistogramBuckets[GenAI.Metric.invokeAgentDuration]?.last
                == .milliseconds(409_600))
        #expect(GenAI.durationHistogramBuckets.count == 4)
    }
}

private actor Rounds {
    var count = 0
    func next() -> Int {
        defer { count += 1 }
        return count
    }
}

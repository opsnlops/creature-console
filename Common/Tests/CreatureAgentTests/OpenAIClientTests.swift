import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import creature_agent

@Suite("OpenAI in world mode")
struct OpenAIClientTests {
    private let transcript = [
        LocalLLMClient.Message(role: .system, content: "You are Beaky."),
        LocalLLMClient.Message(role: .user, content: "April: hello"),
        LocalLLMClient.Message(role: .assistant, content: "Hello April."),
        LocalLLMClient.Message(role: .user, content: "April: what time is it?"),
    ]

    @Test("The transcript becomes instructions plus input items; effort replaces temperature")
    func requestBodyShape() throws {
        let plain = try body(reasoningEffort: nil)
        #expect(plain["model"] as? String == "gpt-6-astra")
        #expect(plain["instructions"] == nil)
        let input = try #require(plain["input"] as? [[String: Any]])
        #expect(input.map { $0["role"] as? String } == ["developer", "user", "assistant", "user"])
        let contents = input.map { ($0["content"] as? [[String: String]])?.first }
        #expect(contents[0]?["type"] == "input_text")
        #expect(contents[0]?["text"] == "You are Beaky.")
        #expect(contents[2]?["type"] == "output_text")
        #expect(contents[2]?["text"] == "Hello April.")
        #expect(contents[3]?["text"] == "April: what time is it?")
        #expect(plain["temperature"] as? Double == 0.9)
        #expect(plain["reasoning"] == nil)
        #expect(plain["stream"] as? Bool == true)
        #expect(plain["store"] as? Bool == false)
        #expect(
            ((plain["text"] as? [String: Any])?["format"] as? [String: String])?["type"] == "text")

        let reasoning = try body(reasoningEffort: "low")
        #expect((reasoning["reasoning"] as? [String: String])?["effort"] == "low")
        #expect(reasoning["temperature"] == nil)
        #expect(plain["service_tier"] == nil)
        #expect(
            try body(reasoningEffort: "low", serviceTier: "fast")["service_tier"] as? String
                == "fast")
    }

    @Test("With tools, the body carries WorldMCP as a remote MCP tool, read only, no approvals")
    func requestBodyCarriesTools() throws {
        let tools = ModelTools(
            serverLabel: "world", serverURL: URL(string: "https://example.test/world/mcp")!,
            allowedTools: ["query_entity", "query_day"], onCall: { _ in })
        let client = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "unused", temperature: 0.9,
            reasoningEffort: nil, logger: Logger(label: "openai-tests"), traceResponses: false)
        let with = try #require(
            client.makeRequest(for: transcript, stream: true, tools: tools).httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: with) as? [String: Any])
        let listed = try #require(body["tools"] as? [[String: Any]])
        #expect(listed.count == 1)
        #expect(listed[0]["type"] as? String == "mcp")
        #expect(listed[0]["server_label"] as? String == "world")
        #expect(listed[0]["server_url"] as? String == "https://example.test/world/mcp")
        #expect(listed[0]["allowed_tools"] as? [String] == ["query_entity", "query_day"])
        #expect(listed[0]["require_approval"] as? String == "never")
        let without = try #require(client.makeRequest(for: transcript, stream: true).httpBody)
        #expect(
            (try JSONSerialization.jsonObject(with: without) as? [String: Any])?["tools"] == nil)
    }

    @Test(
        "A completed MCP call in the stream is a call, not words; a whole response lists its calls")
    func toolCallsAreReported() throws {
        let done =
            #"{"type":"response.output_item.done","output_index":0,"item":{"id":"mcp_1","type":"mcp_call","server_label":"world","name":"query_entity","arguments":"{\"entity_id\":\"person:jesse\"}","output":"{\"facts\":[]}","error":null}}"#
        let call = try #require(OpenAIResponseParser.streamedToolCall(fromData: done))
        #expect(call.name == "query_entity")
        #expect(call.server == "world")
        #expect(call.arguments == #"{"entity_id":"person:jesse"}"#)
        #expect(call.output == #"{"facts":[]}"#)
        #expect(call.error == nil)
        #expect(OpenAIResponseParser.streamedDelta(fromData: done) == nil)
        #expect(
            OpenAIResponseParser.streamedToolCall(
                fromData:
                    #"{"type":"response.output_item.done","item":{"type":"message","content":[]}}"#
            ) == nil)
        #expect(
            OpenAIResponseParser.streamedToolCall(
                fromData: #"{"type":"response.output_text.delta","delta":"Hi"}"#) == nil)

        let whole =
            #"{"output":[{"type":"mcp_list_tools","server_label":"world","tools":[]},{"type":"mcp_call","server_label":"world","name":"query_day","arguments":"{\"day\":\"2026-09-15\"}","output":null,"error":"timed out"},{"type":"message","content":[{"type":"output_text","text":"Nothing much."}]}]}"#
        let calls = OpenAIResponseParser.toolCalls(from: Data(whole.utf8))
        #expect(calls.map(\.name) == ["query_day"])
        #expect(calls.first?.error == "timed out")
        #expect(try OpenAIResponseParser.outputText(from: Data(whole.utf8)) == "Nothing much.")
    }

    @Test("Only output_text deltas carry words; lifecycle events and [DONE] are ignored")
    func streamedDeltas() {
        #expect(
            OpenAIResponseParser.streamedDelta(
                from: #"data: {"type":"response.output_text.delta","delta":"Hello "}"#)
                == "Hello ")
        #expect(
            OpenAIResponseParser.streamedDelta(
                from: #"data: {"type":"response.created","response":{"id":"r1"}}"#) == nil)
        #expect(
            OpenAIResponseParser.streamedDelta(
                from: #"data: {"type":"response.completed","response":{}}"#) == nil)
        #expect(OpenAIResponseParser.streamedDelta(from: "data: [DONE]") == nil)
        #expect(OpenAIResponseParser.streamedDelta(from: "event: response.created") == nil)
        #expect(OpenAIResponseParser.streamedDelta(from: "") == nil)
    }

    @Test("A streamed response arrives sentence by sentence, the same as from the local model")
    func streamsSentences() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.post("v1/responses") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            let json = try JSONSerialization.jsonObject(with: Data(buffer: body)) as? [String: Any]
            #expect(json?["stream"] as? Bool == true)
            #expect(request.headers[.authorization] == "Bearer sk-test")
            var events = "event: response.created\ndata: {\"type\":\"response.created\"}\n\n"
            for delta in ["It is ", "almost midnight, April. ", "Off to bed", " with you."] {
                events +=
                    "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"\(delta)\"}\n\n"
            }
            events += "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
            return Response(
                status: .ok, headers: [.contentType: "text/event-stream"],
                body: .init(byteBuffer: ByteBuffer(string: events)))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let sentences: [String] = try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await httpClient.shutdown() } }
            let client = OpenAIClient(
                apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "You are Beaky.",
                temperature: 1, reasoningEffort: "low",
                endpoint: URL(string: "http://localhost:\(port)/v1/responses")!,
                streamingClient: httpClient,
                logger: Logger(label: "openai-tests"), traceResponses: false)
            var collected: [String] = []
            for await sentence in client.respondStreaming(messages: transcript) {
                collected.append(sentence)
            }
            return collected
        }

        #expect(sentences == ["It is almost midnight, April.", "Off to bed with you."])
    }

    private func body(reasoningEffort: String?, serviceTier: String? = nil) throws -> [String: Any]
    {
        let client = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "unused", temperature: 0.9,
            reasoningEffort: reasoningEffort, serviceTier: serviceTier,
            logger: Logger(label: "openai-tests"), traceResponses: false)
        let request = client.makeRequest(for: transcript, stream: true)
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@Suite("Sentence assembly")
struct SentenceAssemblerTests {
    @Test("Sentences are released at boundaries; the tail waits for flush")
    func assemblesSentences() {
        var assembler = SentenceAssembler()
        #expect(assembler.feed("Hello April. How ") == ["Hello April."])
        #expect(assembler.feed("are you?\"Fine") == ["How are you?"])
        #expect(assembler.feed(" then") == [])
        #expect(assembler.flush() == "Fine then")
        #expect(assembler.flush() == nil)
    }

    @Test("Short sentences wait for company, think blocks vanish, quotes are dropped")
    func minimumsAndThinking() {
        var assembler = SentenceAssembler(minimumCharacters: 12)
        #expect(assembler.feed("Bawk! Hello there April. ") == ["Bawk! Hello there April."])
        var thinking = SentenceAssembler()
        #expect(thinking.feed("<think>plan the reply</think>\"Yes. \"") == ["Yes."])
        #expect(thinking.flush() == nil)
    }
}

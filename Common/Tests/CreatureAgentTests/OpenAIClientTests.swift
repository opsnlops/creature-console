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

        #expect(plain["prompt_cache_key"] == nil)
        let keyed = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "unused", temperature: 0.9,
            cacheKey: "character:beaky", logger: Logger(label: "openai-tests"),
            traceResponses: false)
        let keyedData = try #require(keyed.makeRequest(for: transcript, stream: true).httpBody)
        let keyedBody = try #require(
            JSONSerialization.jsonObject(with: keyedData) as? [String: Any])
        #expect(keyedBody["prompt_cache_key"] as? String == "character:beaky")
        #expect(keyedBody["store"] as? Bool == false)
        #expect(keyedBody["prompt_cache_retention"] == nil)
        // The cache knobs, by experiment: stored responses, no key, a retention.
        let knobbed = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "unused", temperature: 0.9,
            cacheKey: "character:beaky",
            cache: LLMCacheSettings(store: true, key: false, retention: "24h"),
            logger: Logger(label: "openai-tests"), traceResponses: false)
        let knobbedData = try #require(knobbed.makeRequest(for: transcript, stream: true).httpBody)
        let knobbedBody = try #require(
            JSONSerialization.jsonObject(with: knobbedData) as? [String: Any])
        #expect(knobbedBody["store"] as? Bool == true)
        #expect(knobbedBody["prompt_cache_key"] == nil)
        #expect(knobbedBody["prompt_cache_retention"] as? String == "24h")

        let reasoning = try body(reasoningEffort: "low")
        #expect((reasoning["reasoning"] as? [String: String])?["effort"] == "low")
        #expect(reasoning["temperature"] == nil)
        #expect(plain["service_tier"] == nil)
        #expect(
            try body(reasoningEffort: "low", serviceTier: "fast")["service_tier"] as? String
                == "fast")
    }

    @Test(
        "With tools, the body carries the world's tools as functions; after a round, the call and its answer ride along"
    )
    func requestBodyCarriesTools() throws {
        let tools = [
            WorldMCPClient.ToolDefinition(
                name: "query_entity", description: "One entity, whole.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(["entity_id": .object(["type": .string("string")])]),
                    "required": .array([.string("entity_id")]),
                ]))
        ]
        let client = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6-astra", systemPrompt: "unused", temperature: 0.9,
            reasoningEffort: nil, logger: Logger(label: "openai-tests"), traceResponses: false)
        let call = OpenAIResponseParser.FunctionCall(
            callID: "call_1", name: "query_entity", arguments: #"{"entity_id":"person:jesse"}"#)
        let with = try #require(
            client.makeRequest(
                for: transcript, stream: true, tools: tools,
                extra: [.functionCall(call), .functionCallOutput(callID: "call_1", output: "{}")]
            ).httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: with) as? [String: Any])
        let listed = try #require(body["tools"] as? [[String: Any]])
        #expect(listed.count == 1)
        #expect(listed[0]["type"] as? String == "function")
        #expect(listed[0]["name"] as? String == "query_entity")
        #expect(listed[0]["description"] as? String == "One entity, whole.")
        #expect((listed[0]["parameters"] as? [String: Any])?["type"] as? String == "object")
        #expect(listed[0]["strict"] as? Bool == false)
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == transcript.count + 2)
        #expect(input[4]["type"] as? String == "function_call")
        #expect(input[4]["call_id"] as? String == "call_1")
        #expect(input[4]["name"] as? String == "query_entity")
        #expect(input[5]["type"] as? String == "function_call_output")
        #expect(input[5]["output"] as? String == "{}")
        let without = try #require(client.makeRequest(for: transcript, stream: true).httpBody)
        #expect(
            (try JSONSerialization.jsonObject(with: without) as? [String: Any])?["tools"] == nil)
    }

    @Test(
        "A completed function call in the stream is a call, not words; a whole response lists its calls"
    )
    func functionCallsAreParsed() throws {
        let done =
            #"{"type":"response.output_item.done","output_index":0,"item":{"id":"fc_1","type":"function_call","call_id":"call_1","name":"query_entity","arguments":"{\"entity_id\":\"person:jesse\"}","status":"completed"}}"#
        let call = try #require(OpenAIResponseParser.streamedFunctionCall(fromData: done))
        #expect(call.callID == "call_1")
        #expect(call.name == "query_entity")
        #expect(call.arguments == #"{"entity_id":"person:jesse"}"#)
        #expect(OpenAIResponseParser.streamedDelta(fromData: done) == nil)
        #expect(
            OpenAIResponseParser.streamedFunctionCall(
                fromData:
                    #"{"type":"response.output_item.done","item":{"type":"message","content":[]}}"#
            ) == nil)
        #expect(
            OpenAIResponseParser.streamedFunctionCall(
                fromData: #"{"type":"response.output_text.delta","delta":"Hi"}"#) == nil)

        let whole =
            #"{"output":[{"type":"function_call","call_id":"call_2","name":"query_day","arguments":"{\"day\":\"2026-09-15\"}"},{"type":"message","content":[{"type":"output_text","text":"Nothing much."}]}]}"#
        let calls = OpenAIResponseParser.functionCalls(from: Data(whole.utf8))
        #expect(
            calls == [
                .init(callID: "call_2", name: "query_day", arguments: #"{"day":"2026-09-15"}"#)
            ])
        #expect(try OpenAIResponseParser.outputText(from: Data(whole.utf8)) == "Nothing much.")
    }

    @Test("The mind runs the loop: a round that asks for a tool is answered, then the words stream")
    func runsTheToolLoop() async throws {
        let rounds = Rounds()
        let router = Router(context: BasicRequestContext.self)
        router.post("v1/responses") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            let json = try JSONSerialization.jsonObject(with: Data(buffer: body)) as? [String: Any]
            let input = json?["input"] as? [[String: Any]] ?? []
            let round = try await rounds.next(input: input)
            var events = "event: response.created\ndata: {\"type\":\"response.created\"}\n\n"
            if round == 0 {
                // The model asks; the arguments arrive whole with the item.
                events +=
                    "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"call_id\":\"call_9\",\"name\":\"query_entity\",\"arguments\":\"{\\\"entity_id\\\":\\\"person:jesse\\\"}\"}}\n\n"
            } else {
                for delta in ["Jesse is your contractor, April. ", "He was here Sunday."] {
                    events +=
                        "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"\(delta)\"}\n\n"
                }
            }
            events += "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
            return Response(
                status: .ok, headers: [.contentType: "text/event-stream"],
                body: .init(byteBuffer: ByteBuffer(string: events)))
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let records = Records()
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
            let tools = ModelTools(
                serverLabel: "world",
                catalogue: {
                    [
                        WorldMCPClient.ToolDefinition(
                            name: "query_entity", description: "", inputSchema: .object([:]))
                    ]
                },
                call: { name, arguments in
                    #expect(name == "query_entity")
                    #expect(arguments == #"{"entity_id":"person:jesse"}"#)
                    return #"{"facts":[{"predicate":"person.relationship","value":"contractor"}]}"#
                },
                onCall: { await records.note($0) })
            var collected: [String] = []
            for await sentence in client.respondStreaming(messages: transcript, tools: tools) {
                collected.append(sentence)
            }
            return collected
        }

        #expect(sentences == ["Jesse is your contractor, April.", "He was here Sunday."])
        // The second round carried the call and its answer back to the model.
        let second =
            try JSONSerialization.jsonObject(with: Data(await rounds.json(ofRound: 1).utf8))
            as? [[String: Any]] ?? []
        #expect(second.count == transcript.count + 2)
        #expect(second[transcript.count]["type"] as? String == "function_call")
        #expect(second[transcript.count + 1]["type"] as? String == "function_call_output")
        #expect(
            (second[transcript.count + 1]["output"] as? String)?.contains("contractor") == true)
        let recorded = await records.calls
        #expect(recorded.map(\.name) == ["query_entity"])
        #expect(recorded.first?.output?.contains("contractor") == true)
        #expect(recorded.first?.error == nil)
    }

    @Test("What a call cost is read from usage: whole responses and the stream's closing event")
    func usageIsParsed() throws {
        let whole =
            #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Hi"}]}],"usage":{"input_tokens":4812,"input_tokens_details":{"cached_tokens":3072},"output_tokens":41,"total_tokens":4853}}"#
        let parsed = try #require(OpenAIResponseParser.usage(from: Data(whole.utf8)))
        #expect(parsed.inputTokens == 4812)
        #expect(parsed.cachedTokens == 3072)
        #expect(parsed.outputTokens == 41)
        #expect(parsed.raw.contains("\"cached_tokens\":3072"))
        #expect(OpenAIResponseParser.usage(from: Data(#"{"output":[]}"#.utf8)) == nil)
        let completed =
            #"{"type":"response.completed","response":{"id":"r1","usage":{"input_tokens":900,"input_tokens_details":{"cached_tokens":0},"output_tokens":12}}}"#
        let usage = try #require(OpenAIResponseParser.streamedUsage(fromData: completed))
        #expect((usage.inputTokens, usage.cachedTokens, usage.outputTokens) == (900, 0, 12))
        #expect(usage.uncachedTokens == 900)
        #expect(usage.raw.contains("\"input_tokens\":900"))
        #expect(
            OpenAIResponseParser.streamedUsage(
                fromData: #"{"type":"response.output_text.delta","delta":"Hi"}"#) == nil)
        #expect(OpenAIResponseParser.streamedDelta(fromData: completed) == nil)
        #expect(LLMUsage(inputTokens: 10, cachedTokens: 30, outputTokens: 1).uncachedTokens == 0)
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

/// Each round's input items, kept as the JSON text (a `[String: Any]` cannot leave an actor).
private actor Rounds {
    var inputs: [String] = []
    func next(input: [[String: Any]]) throws -> Int {
        inputs.append(
            String(decoding: try JSONSerialization.data(withJSONObject: input), as: UTF8.self))
        return inputs.count - 1
    }
    func json(ofRound round: Int) -> String { inputs[round] }
}

private actor Records {
    var calls: [ModelTools.Call] = []
    func note(_ call: ModelTools.Call) { calls.append(call) }
}

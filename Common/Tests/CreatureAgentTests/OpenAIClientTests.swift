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
        #expect(plain["model"] as? String == "gpt-6")
        #expect(plain["instructions"] as? String == "You are Beaky.")
        let input = try #require(plain["input"] as? [[String: String]])
        #expect(input.map { $0["role"]! } == ["user", "assistant", "user"])
        #expect(input.last?["content"] == "April: what time is it?")
        #expect(plain["temperature"] as? Double == 0.9)
        #expect(plain["reasoning"] == nil)
        #expect(plain["stream"] as? Bool == true)

        let reasoning = try body(reasoningEffort: "low")
        #expect((reasoning["reasoning"] as? [String: String])?["effort"] == "low")
        #expect(reasoning["temperature"] == nil)
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
            let client = OpenAIClient(
                apiKey: "sk-test", model: "gpt-6", systemPrompt: "You are Beaky.",
                temperature: 1, reasoningEffort: "low",
                endpoint: URL(string: "http://localhost:\(port)/v1/responses")!,
                logger: Logger(label: "openai-tests"), traceResponses: false)
            var collected: [String] = []
            for await sentence in client.respondStreaming(messages: transcript) {
                collected.append(sentence)
            }
            return collected
        }

        #expect(sentences == ["It is almost midnight, April.", "Off to bed with you."])
    }

    private func body(reasoningEffort: String?) throws -> [String: Any] {
        let client = OpenAIClient(
            apiKey: "sk-test", model: "gpt-6", systemPrompt: "unused", temperature: 0.9,
            reasoningEffort: reasoningEffort, logger: Logger(label: "openai-tests"),
            traceResponses: false)
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

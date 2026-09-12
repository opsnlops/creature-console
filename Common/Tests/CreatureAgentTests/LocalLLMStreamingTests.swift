import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import creature_agent

@Suite("Local LLM streaming")
struct LocalLLMStreamingTests {
    @Test("A reply cut off by max_tokens ends on its last complete sentence (#157)")
    func tokenCapDropsTheUnfinishedSentence() async throws {
        let sentences = try await stream(
            chunks: [
                ("Once upon a time, there was a parrot. ", nil),
                ("She lived in a purple house. ", nil),
                ("Together they turned it into a sanctuary for all the", "length"),
            ]
        )

        #expect(
            sentences == ["Once upon a time, there was a parrot.", "She lived in a purple house."])
    }

    @Test("A reply that finishes naturally keeps its unpunctuated tail")
    func naturalStopKeepsTheTail() async throws {
        let sentences = try await stream(
            chunks: [("Bawk, hello April. ", nil), ("Ready when you are", "stop")]
        )

        #expect(sentences == ["Bawk, hello April.", "Ready when you are"])
    }

    /// Serves one scripted OpenAI-style completion stream on loopback and collects what the
    /// client yields as sentences.
    private func stream(chunks: [(String, String?)]) async throws -> [String] {
        let router = Router(context: BasicRequestContext.self)
        router.post("v1/chat/completions") { _, _ in
            var body = ""
            for (content, finish) in chunks {
                let finishJSON = finish.map { "\"\($0)\"" } ?? "null"
                let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
                body +=
                    "data: {\"choices\":[{\"delta\":{\"content\":\"\(escaped)\"},\"finish_reason\":\(finishJSON)}]}\n\n"
            }
            body += "data: [DONE]\n\n"
            return Response(
                status: .ok,
                headers: [.contentType: "text/event-stream"],
                body: .init(byteBuffer: ByteBuffer(string: body))
            )
        }
        let application = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        return try await application.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = LocalLLMClient(
                host: "localhost",
                port: port,
                model: "test",
                systemPrompt: "You are Beaky.",
                temperature: 0.5,
                maxTokens: 40,
                conversationHistorySize: 0,
                logger: Logger(label: "local-llm-streaming-tests"),
                traceResponses: false
            )
            var sentences: [String] = []
            for await sentence in client.respondStreaming(
                messages: [.init(role: .user, content: "Tell me a story")],
                recordingHistoryFor: nil
            ) {
                sentences.append(sentence)
            }
            return sentences
        }
    }
}

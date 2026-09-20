import Foundation
import Logging
import Testing

@testable import creature_agent

@Suite("The Batch API's file shapes")
struct OpenAIBatchTests {
    @Test(
        "A request is one line: custom id, method, url, and the body as it would have been posted")
    func lineShape() throws {
        let body = Data(#"{"model":"gpt-6-astra","input":[{"role":"user","content":"hi"}]}"#.utf8)
        let line = try OpenAIBatchClient.line(
            customID: "memory:2026-09-19:run:episodes", endpoint: "/v1/responses", body: body)
        let object = try #require(JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["custom_id"] as? String == "memory:2026-09-19:run:episodes")
        #expect(object["method"] as? String == "POST")
        #expect(object["url"] as? String == "/v1/responses")
        let inner = try #require(object["body"] as? [String: Any])
        #expect(inner["model"] as? String == "gpt-6-astra")
        // Keys sorted, as every request is: the same prompt is the same bytes.
        #expect(String(decoding: line, as: UTF8.self).hasPrefix(#"{"body":{"input""#))
        // The memory's own request goes through the same shape, JSON mode and all.
        let client = OpenAIClient(
            apiKey: "k", model: "gpt-6-astra", systemPrompt: "", temperature: 0.7,
            logger: Logger(label: "batch-tests"), traceResponses: false)
        let memoryLine = try client.batchLine(
            for: [LocalLLMClient.Message(role: .user, content: "remember")], customID: "c")
        let memory = try #require(JSONSerialization.jsonObject(with: memoryLine) as? [String: Any])
        let memoryBody = try #require(memory["body"] as? [String: Any])
        #expect(memoryBody["model"] as? String == "gpt-6-astra")
        #expect((memoryBody["text"] as? [String: Any]) != nil)
    }

    @Test("The answer to one request is found in the output file; failures say why")
    func results() throws {
        let output = Data(
            """
            {"id":"batch_req_1","custom_id":"a","response":{"status_code":200,"request_id":"r1","body":{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"{\\"episodes\\":[]}"}]}],"usage":{"input_tokens":10,"output_tokens":2}}},"error":null}
            {"id":"batch_req_2","custom_id":"b","response":{"status_code":429,"request_id":"r2","body":{"error":{"message":"rate limited"}}},"error":null}
            {"id":"batch_req_3","custom_id":"c","response":null,"error":{"code":"invalid","message":"bad request"}}

            """.utf8)
        let answer = try OpenAIBatchClient.result(for: "a", in: output)
        let object = try #require(JSONSerialization.jsonObject(with: answer) as? [String: Any])
        #expect(object["id"] as? String == "resp_1")
        #expect(try OpenAIResponseParser.outputText(from: answer) == #"{"episodes":[]}"#)
        #expect(OpenAIResponseParser.usage(from: answer)?.inputTokens == 10)
        #expect(
            throws: OpenAIBatchError.requestFailed(
                "HTTP 429: {\"error\":{\"message\":\"rate limited\"}}")
        ) {
            try OpenAIBatchClient.result(for: "b", in: output)
        }
        #expect(throws: OpenAIBatchError.requestFailed("bad request")) {
            try OpenAIBatchClient.result(for: "c", in: output)
        }
        #expect(throws: OpenAIBatchError.missing("d")) {
            try OpenAIBatchClient.result(for: "d", in: output)
        }
    }
}

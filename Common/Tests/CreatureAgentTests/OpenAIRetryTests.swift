import AsyncHTTPClient
import Foundation
import Logging
import NIOConcurrencyHelpers
import Testing

@testable import creature_agent

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenAI as a script: each request is answered with the next line for its path, and the last
/// line again once the script runs out.
private final class ScriptedOpenAI: Sendable {
    enum Line: Sendable {
        case answer(Int, body: String = "{}", headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private let script: NIOLockedValueBox<[String: [Line]]>
    private let sent = NIOLockedValueBox<[String]>([])

    init(_ script: [String: [Line]]) {
        self.script = NIOLockedValueBox(script)
    }

    var requests: [String] { sent.withLockedValue { $0 } }

    var transport: OpenAIRetry.Transport {
        { request in try self.answer(request) }
    }

    private func answer(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let path = url.path()
        sent.withLockedValue { $0.append(path) }
        let line = try #require(
            script.withLockedValue { script -> Line? in
                guard var lines = script[path], let first = lines.first else { return nil }
                if lines.count > 1 { lines.removeFirst() }
                script[path] = lines
                return first
            })
        switch line {
        case .failure(let code):
            throw URLError(code)
        case .answer(let status, let body, let headers):
            let response = try #require(
                HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
            return (Data(body.utf8), response)
        }
    }
}

/// OpenAI's front door, the night Mango's beliefs were lost.
private let frontDoor =
    "upstream connect error or disconnect/reset before headers. reset reason: remote connection failure"

@Suite("A request OpenAI could not take is sent again (#268)")
struct OpenAIRetryTests {
    private let logger = Logger(label: "openai-retry-tests")
    private let waits = NIOLockedValueBox<[Duration]>([])

    private func policy(
        retries: Int = 2, longestWait: Duration = .seconds(8), retriesTimeouts: Bool = false
    ) -> OpenAIRetry {
        let waits = waits
        return OpenAIRetry(
            retries: retries, longestWait: longestWait, retriesTimeouts: retriesTimeouts,
            sleep: { wait in waits.withLockedValue { $0.append(wait) } })
    }

    private func request(_ path: String) -> URLRequest {
        URLRequest(url: OpenAIBatchClient.defaultBaseURL.appending(path: path))
    }

    private func status(_ answered: (Data, URLResponse)) -> Int? {
        (answered.1 as? HTTPURLResponse)?.statusCode
    }

    @Test("A 503 is sent again after a short wait, and the answer after it is the one kept")
    func fiveOhThreeIsSentAgain() async throws {
        let openAI = ScriptedOpenAI([
            "/v1/batches/b": [.answer(503, body: frontDoor), .answer(200)]
        ])
        let answered = try await policy().data(
            for: request("batches/b"), "batch status", logger: logger,
            transport: openAI.transport)
        #expect(status(answered) == 200)
        #expect(openAI.requests.count == 2)
        let wait = try #require(waits.withLockedValue { $0 }.first)
        #expect(wait >= .milliseconds(375) && wait <= .milliseconds(500))
    }

    @Test("The time the provider asks for is the wait, up to the longest wait")
    func retryAfterIsHonoured() async throws {
        let openAI = ScriptedOpenAI([
            "/v1/responses": [
                .answer(429, headers: ["retry-after-ms": "1500"]),
                .answer(429, headers: ["retry-after": "30"]),
                .answer(200),
            ]
        ])
        let answered = try await policy().data(
            for: request("responses"), "responses", logger: logger, transport: openAI.transport)
        #expect(status(answered) == 200)
        #expect(waits.withLockedValue { $0 } == [.milliseconds(1500), .seconds(8)])
        #expect(OpenAIRetry.retryAfter(ms: nil, seconds: "2") == .seconds(2))
        #expect(OpenAIRetry.retryAfter(ms: nil, seconds: "120") == nil)
        #expect(OpenAIRetry.retryAfter(ms: "soon", seconds: nil) == nil)
        #expect(OpenAIRetry.retryAfter(ms: nil, seconds: nil) == nil)
    }

    @Test(
        "A request refused for good is not sent again; its answer is the caller's",
        arguments: [400, 401, 404])
    func refusedIsNotSentAgain(_ code: Int) async throws {
        let openAI = ScriptedOpenAI(["/v1/responses": [.answer(code), .answer(200)]])
        let answered = try await policy().data(
            for: request("responses"), "responses", logger: logger, transport: openAI.transport)
        #expect(status(answered) == code)
        #expect(openAI.requests.count == 1)
        #expect(waits.withLockedValue { $0 }.isEmpty)
    }

    @Test("When the tries run out, the last answer is the caller's, after waits that double")
    func triesRunOut() async throws {
        let openAI = ScriptedOpenAI(["/v1/responses": [.answer(503, body: frontDoor)]])
        let answered = try await policy().data(
            for: request("responses"), "responses", logger: logger, transport: openAI.transport)
        #expect(status(answered) == 503)
        #expect(openAI.requests.count == 3)
        let waits = waits.withLockedValue { $0 }
        #expect(waits.count == 2)
        #expect(waits[1] >= .milliseconds(750) && waits[1] <= .seconds(1))
    }

    @Test("A dropped connection is sent again; a timeout only where nobody is waiting")
    func connectionsAndTimeouts() async throws {
        let dropped = ScriptedOpenAI([
            "/v1/responses": [.failure(.networkConnectionLost), .answer(200)]
        ])
        let answered = try await policy().data(
            for: request("responses"), "responses", logger: logger, transport: dropped.transport)
        #expect(status(answered) == 200)

        let slow = ScriptedOpenAI(["/v1/responses": [.failure(.timedOut), .answer(200)]])
        await #expect(throws: URLError.self) {
            _ = try await policy().data(
                for: request("responses"), "responses", logger: logger,
                transport: slow.transport)
        }
        #expect(slow.requests.count == 1)
        let slowAtNight = ScriptedOpenAI(["/v1/responses": [.failure(.timedOut), .answer(200)]])
        let night = try await policy(retriesTimeouts: true).data(
            for: request("responses"), "responses", logger: logger,
            transport: slowAtNight.transport)
        #expect(status(night) == 200)
        #expect(slowAtNight.requests.count == 2)
    }

    @Test("What is worth sending again: OpenAI's SDKs' statuses and failed connections")
    func whatIsTransient() {
        for code in [408, 409, 429, 500, 502, 503, 504] {
            #expect(OpenAIRetry.isTransient(status: code))
        }
        for code in [200, 400, 401, 403, 404, 422] {
            #expect(!OpenAIRetry.isTransient(status: code))
        }
        let live = OpenAIRetry.live
        let night = OpenAIRetry.night
        #expect(live.isTransient(OpenAIClientError.httpError(code: 503, body: frontDoor)))
        #expect(!live.isTransient(OpenAIClientError.httpError(code: 401, body: "")))
        // The live reply lost on 2026-10-21.
        #expect(live.isTransient(HTTPClientError.connectTimeout))
        #expect(live.isTransient(HTTPClientError.remoteConnectionClosed))
        #expect(!live.isTransient(HTTPClientError.readTimeout))
        #expect(night.isTransient(HTTPClientError.readTimeout))
        #expect(!live.isTransient(URLError(.timedOut)))
        #expect(night.isTransient(URLError(.timedOut)))
        #expect(!night.isTransient(URLError(.badURL)))
        #expect(!night.isTransient(CancellationError()))
    }

    @Test("The wait doubles, jittered down by up to a quarter, and stops at the longest")
    func backoffDoubles() {
        let night = OpenAIRetry.night
        for _ in 0..<20 {
            let first = night.backoff(0)
            #expect(first >= .milliseconds(750) && first <= .seconds(1))
            let fourth = night.backoff(3)
            #expect(fourth >= .seconds(6) && fourth <= .seconds(8))
            let late = night.backoff(40)
            #expect(late >= .seconds(45) && late <= .seconds(60))
        }
    }

    // MARK: - The batch

    private static let completed = #"{"status": "completed", "output_file_id": "file-out"}"#
    private static let output = #"{"custom_id": "memory:x:episodes"}"#

    @Test("A look at the batch that fails on the way is a look missed, not the end of the wait")
    func missedLookIsNotTheEnd() async throws {
        let openAI = ScriptedOpenAI([
            "/v1/batches/batch-1": [
                .answer(503, body: frontDoor),
                .answer(200, body: #"{"status": "in_progress"}"#),
                .failure(.networkConnectionLost),
                .answer(200, body: Self.completed),
            ],
            "/v1/files/file-out/content": [.answer(200, body: Self.output)],
        ])
        let batches = OpenAIBatchClient(
            apiKey: "test", logger: logger, retry: policy(retries: 0, retriesTimeouts: true),
            transport: openAI.transport)
        let output = try await batches.output(
            of: "batch-1", every: .milliseconds(1), deadline: Date().addingTimeInterval(60))
        #expect(String(decoding: output, as: UTF8.self) == Self.output)
        #expect(openAI.requests.filter { $0 == "/v1/batches/batch-1" }.count == 4)
    }

    @Test("A look refused for good still ends the wait")
    func refusedLookEndsTheWait() async throws {
        let openAI = ScriptedOpenAI([
            "/v1/batches/batch-1": [.answer(401, body: #"{"error": "invalid key"}"#)]
        ])
        let batches = OpenAIBatchClient(
            apiKey: "test", logger: logger, retry: policy(), transport: openAI.transport)
        await #expect(throws: OpenAIClientError.self) {
            _ = try await batches.output(
                of: "batch-1", every: .milliseconds(1), deadline: Date().addingTimeInterval(60))
        }
        #expect(openAI.requests.count == 1)
    }

    @Test("Uploading and submitting a batch ride out a 503")
    func submitRidesOutAFiveOhThree() async throws {
        let openAI = ScriptedOpenAI([
            "/v1/files": [
                .answer(503, body: frontDoor), .answer(200, body: #"{"id": "file-in"}"#),
            ],
            "/v1/batches": [.answer(502), .answer(200, body: #"{"id": "batch-9"}"#)],
        ])
        let batches = OpenAIBatchClient(
            apiKey: "test", logger: logger, retry: policy(), transport: openAI.transport)
        let id = try await batches.submit(lines: [Data(#"{"custom_id": "a"}"#.utf8)])
        #expect(id == "batch-9")
        #expect(openAI.requests == ["/v1/files", "/v1/files", "/v1/batches", "/v1/batches"])
    }
}

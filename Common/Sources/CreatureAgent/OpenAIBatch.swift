import Foundation
import Logging
import Tracing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenAI's Batch API: a JSONL file of requests, a batch that runs them within a day, and an
/// output file of answers - at half the price. The nightly memory is the textbook case: one
/// call at 3:30 AM that nobody is waiting on. April: "let's look at using the batch API to
/// reduce the cost of the nightly memory processor." (gpt-6-astra: $10 in, $50 out per
/// million; batch is 50% of both.)
struct OpenAIBatchClient: Sendable {
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    /// Where a batch stands, as the provider reports it.
    enum Status: Equatable, Sendable {
        /// validating, in_progress, finalizing, cancelling: not yet.
        case pending(String)
        case completed(outputFileID: String?, errorFileID: String?)
        /// failed, expired, cancelled: the answers are not coming.
        case finished(String)
    }

    private let baseURL: URL
    private let apiKey: String
    private let logger: Logger

    init(apiKey: String, baseURL: URL = OpenAIBatchClient.defaultBaseURL, logger: Logger) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.logger = logger
    }

    /// One request as a line of the batch file: `body` is exactly what the synchronous call
    /// would have posted to `endpoint`.
    static func line(customID: String, endpoint: String, body: Data) throws -> Data {
        let request: [String: Any] = [
            "custom_id": customID, "method": "POST", "url": endpoint,
            "body": try JSONSerialization.jsonObject(with: body),
        ]
        return try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    }

    /// Uploads the requests and starts the batch; returns its id.
    func submit(
        lines: [Data], endpoint: String = "/v1/responses", metadata: [String: String] = [:]
    ) async throws -> String {
        let file = Data(lines.map { $0 + Data("\n".utf8) }.joined())
        let fileID = try await upload(file, name: "memory-\(UUID().uuidString.lowercased()).jsonl")
        var body: [String: Any] = [
            "input_file_id": fileID, "endpoint": endpoint, "completion_window": "24h",
        ]
        if !metadata.isEmpty { body["metadata"] = metadata }
        let response = try await post(
            path: "batches", body: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json")
        guard let id = response["id"] as? String else {
            throw OpenAIBatchError.malformed("batch id")
        }
        logger.info(
            "Batch submitted",
            metadata: ["llm.batch.id": "\(id)", "llm.batch.requests": "\(lines.count)"])
        return id
    }

    func status(of batchID: String) async throws -> Status {
        let object = try await get(path: "batches/\(batchID)")
        guard let status = object["status"] as? String else {
            throw OpenAIBatchError.malformed("batch status")
        }
        switch status {
        case "completed":
            return .completed(
                outputFileID: object["output_file_id"] as? String,
                errorFileID: object["error_file_id"] as? String)
        case "failed", "expired", "cancelled":
            return .finished(status)
        default:
            return .pending(status)
        }
    }

    func cancel(batchID: String) async throws {
        _ = try await post(path: "batches/\(batchID)/cancel", body: Data(), contentType: nil)
    }

    /// The output file, as it is: one JSON object per line.
    func content(ofFile fileID: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "files/\(fileID)/content"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return data
    }

    /// The answer to one request in an output file: the response body the synchronous call
    /// would have received, or why there is none.
    static func result(for customID: String, in output: Data) throws -> Data {
        for line in output.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                object["custom_id"] as? String == customID
            else { continue }
            if let error = object["error"] as? [String: Any] {
                throw OpenAIBatchError.requestFailed(
                    (error["message"] as? String) ?? String(describing: error))
            }
            guard let response = object["response"] as? [String: Any] else {
                throw OpenAIBatchError.malformed("response")
            }
            let status = (response["status_code"] as? Int) ?? 0
            guard let body = response["body"] else { throw OpenAIBatchError.malformed("body") }
            let data = try JSONSerialization.data(withJSONObject: body)
            guard 200..<300 ~= status else {
                throw OpenAIBatchError.requestFailed(
                    "HTTP \(status): \(String(decoding: data.prefix(300), as: UTF8.self))")
            }
            return data
        }
        throw OpenAIBatchError.missing(customID)
    }

    /// Waits for the batch, looking every `every` (a minute by default) until `deadline`,
    /// and hands back the output file. Past the deadline the batch is cancelled - the night
    /// will be remembered the ordinary way - and a batch the provider gave up on is an error
    /// with its status.
    func output(of batchID: String, every interval: Duration = .seconds(60), deadline: Date)
        async throws -> Data
    {
        var looked = 0
        while true {
            let status = try await status(of: batchID)
            switch status {
            case .completed(let outputFileID, let errorFileID):
                guard let outputFileID else {
                    throw OpenAIBatchError.unfinished(
                        "completed with no output file"
                            + (errorFileID.map { "; errors in \($0)" } ?? ""))
                }
                logger.info(
                    "Batch completed",
                    metadata: ["llm.batch.id": "\(batchID)", "llm.batch.looked": "\(looked)"])
                return try await content(ofFile: outputFileID)
            case .finished(let why):
                throw OpenAIBatchError.unfinished(why)
            case .pending(let stage):
                looked += 1
                if looked == 1 || looked % 10 == 0 {
                    logger.info(
                        "Batch pending",
                        metadata: ["llm.batch.id": "\(batchID)", "llm.batch.status": "\(stage)"])
                }
                if Date() >= deadline {
                    try? await cancel(batchID: batchID)
                    throw OpenAIBatchError.unfinished("still \(stage) at the deadline; cancelled")
                }
                try await Task.sleep(for: interval)
            }
        }
    }

    // MARK: - HTTP

    private func upload(_ file: Data, name: String) async throws -> String {
        let boundary = "creature-\(UUID().uuidString)"
        var body = Data()
        func field(_ text: String) { body += Data(text.utf8) }
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nbatch\r\n")
        field(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/jsonl\r\n\r\n"
        )
        body += file
        field("\r\n--\(boundary)--\r\n")
        let response = try await post(
            path: "files", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        guard let id = response["id"] as? String else {
            throw OpenAIBatchError.malformed("file id")
        }
        return id
    }

    private func post(path: String, body: Data, contentType: String?) async throws
        -> [String: Any]
    {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIBatchError.malformed("json")
        }
        return object
    }

    private func get(path: String) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIBatchError.malformed("json")
        }
        return object
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw OpenAIClientError.httpError(
                code: http.statusCode, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
    }
}

enum OpenAIBatchError: Error, CustomStringConvertible, Equatable {
    /// The batch ended without this answer: failed, expired, cancelled, or past the deadline.
    case unfinished(String)
    /// The batch ran, and this request in it failed.
    case requestFailed(String)
    /// The output file has no line for the request.
    case missing(String)
    case malformed(String)

    var description: String {
        switch self {
        case .unfinished(let why): "the batch did not finish: \(why)"
        case .requestFailed(let why): "the batched request failed: \(why)"
        case .missing(let id): "no answer for \(id) in the batch output"
        case .malformed(let what): "the batch API's answer had no \(what)"
        }
    }
}

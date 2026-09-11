import Common
import Foundation
import WorldCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif


public protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {}

public enum WorldConversationClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidBaseURL
    case unexpectedResponse
    case requestFailed(statusCode: Int)
    case streamingUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The Creature World address is invalid"
        case .unexpectedResponse:
            "Creature World returned an invalid response"
        case .requestFailed(let statusCode):
            "Creature World returned HTTP status \(statusCode)"
        case .streamingUnavailable:
            "Creature World streaming is unavailable on this platform"
        }
    }
}

public typealias WorldConversationUpdateStream = AsyncThrowingStream<Void, any Error>

/// Typed HTTP transport for Creature World's canonical conversation API.
public struct WorldConversationClient: Sendable {
    private let connection: CreatureServiceConnection
    private let loader: any HTTPDataLoading

    public init(
        connection: CreatureServiceConnection,
        loader: any HTTPDataLoading = URLSession.shared
    ) {
        self.connection = connection
        self.loader = loader
    }

    public func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        var request = try request(
            pathComponents: [
                "conversations", utterance.conversationID.rawValue, "utterances",
            ]
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try WorldJSON.makeEncoder().encode(utterance)
        return try await response(UtteranceIngressResult.self, for: request)
    }

    public func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID? = nil,
        limit: Int = 100
    ) async throws -> ConversationItemPage {
        precondition(limit > 0)
        var request = try request(
            pathComponents: ["conversations", conversationID.rawValue, "items"],
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                itemID.map { URLQueryItem(name: "after_item_id", value: $0.rawValue) },
            ].compactMap { $0 }
        )
        request.httpMethod = "GET"
        return try await response(ConversationItemPage.self, for: request)
    }

    public func updates(in conversationID: ConversationID) throws -> WorldConversationUpdateStream {
        var proposedRequest = try request(
            pathComponents: ["conversations", conversationID.rawValue, "stream"]
        )
        proposedRequest.httpMethod = "GET"
        // SSE heartbeats arrive every 15 seconds. Leave enough room for a delayed heartbeat while
        // retaining a finite idle timeout so the reconnect loop can repair a dead connection.
        proposedRequest.timeoutInterval = 60
        let request = proposedRequest

        #if os(macOS) || os(iOS)
            return WorldConversationUpdateStream(bufferingPolicy: .bufferingNewest(1)) {
                continuation in
                let task = Task {
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        try Self.validate(response)
                        for try await line in bytes.lines {
                            guard line == "event: ready" || line == "event: item" else {
                                continue
                            }
                            continuation.yield(())
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        #else
            return WorldConversationUpdateStream {
                $0.finish(throwing: WorldConversationClientError.streamingUnavailable)
            }
        #endif
    }

    private func request(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard
            var url = URL(
                string: connection.baseURLString(transport: .http, pathPrefix: "/world/v1")
            )
        else { throw WorldConversationClientError.invalidBaseURL }
        for component in pathComponents {
            url.append(path: component)
        }
        if !queryItems.isEmpty {
            url.append(queryItems: queryItems)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        connection.applyProxyHeaders(to: &request)
        return request
    }

    private func response<Value: Decodable>(
        _ type: Value.Type,
        for request: URLRequest
    ) async throws -> Value {
        let (data, response) = try await loader.data(for: request)
        try Self.validate(response)
        return try WorldJSON.makeDecoder().decode(type, from: data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw WorldConversationClientError.unexpectedResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw WorldConversationClientError.requestFailed(statusCode: response.statusCode)
        }
    }
}

import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import ServiceLifecycle
import WorldCore

public typealias GatewayConversationByteStream = AsyncThrowingStream<ByteBuffer, any Error>

public protocol CommunicatorWorldUpstream: Sendable {
    func health() async throws
    func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult
    func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage
    func conversationStream(
        for conversationID: ConversationID
    ) async throws -> GatewayConversationByteStream
}

public enum CommunicatorWorldUpstreamError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case requestFailed(statusCode: UInt)
    case responseTooLarge
    case streamFrameTooLarge
    case streamBufferOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The configured Creature World URL is invalid"
        case .requestFailed(let statusCode):
            "Creature World returned HTTP status \(statusCode)"
        case .responseTooLarge:
            "Creature World returned a response larger than the gateway accepts"
        case .streamFrameTooLarge:
            "Creature World returned an SSE frame larger than the gateway accepts"
        case .streamBufferOverflow:
            "The Communicator gateway client could not keep up with Creature World"
        }
    }
}

/// Owns the gateway's pooled World client and gives it a lifecycle-aligned shutdown.
public struct CommunicatorGatewayHTTPClientService: Service, Sendable {
    private let client: HTTPClient

    public init(logger: Logger = Logger(label: "creature-communicator-gateway.http-client")) {
        var configuration = HTTPClient.Configuration()
        configuration.timeout = .init(connect: .seconds(10), read: .seconds(45))
        client = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: configuration,
            backgroundActivityLogger: logger
        )
    }

    public func worldUpstream(baseURL: URL, logger: Logger) -> HTTPCommunicatorWorldUpstream {
        HTTPCommunicatorWorldUpstream(baseURL: baseURL, client: client, logger: logger)
    }

    public func run() async throws {
        do {
            try await gracefulShutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
        try await client.shutdown()
    }
}

/// Linux-capable HTTP transport from the isolated Communicator gateway to Creature World.
/// AsyncHTTPClient automatically carries the active distributed trace context across this hop.
public struct HTTPCommunicatorWorldUpstream: CommunicatorWorldUpstream, Sendable {
    public static let maximumResponseBytes = 1_048_576

    private let baseURL: URL
    private let client: HTTPClient
    private let logger: Logger

    public init(
        baseURL: URL,
        client: HTTPClient = .shared,
        logger: Logger = Logger(label: "creature-communicator-gateway.world-upstream")
    ) {
        self.baseURL = baseURL
        self.client = client
        self.logger = logger
    }

    public func health() async throws {
        let response = try await execute(pathComponents: ["health"])
        try validate(response)
        _ = try await collect(response.body)
    }

    public func submit(_ utterance: PersonUtterance) async throws -> UtteranceIngressResult {
        let body = try WorldJSON.makeEncoder().encode(utterance)
        let response = try await execute(
            pathComponents: [
                "conversations", utterance.conversationID.rawValue, "utterances",
            ],
            method: .POST,
            body: body
        )
        return try await decode(UtteranceIngressResult.self, from: response)
    }

    public func items(
        in conversationID: ConversationID,
        after itemID: ConversationItemID?,
        limit: Int
    ) async throws -> ConversationItemPage {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let itemID {
            queryItems.append(URLQueryItem(name: "after_item_id", value: itemID.rawValue))
        }
        let response = try await execute(
            pathComponents: ["conversations", conversationID.rawValue, "items"],
            queryItems: queryItems
        )
        return try await decode(ConversationItemPage.self, from: response)
    }

    public func conversationStream(
        for conversationID: ConversationID
    ) async throws -> GatewayConversationByteStream {
        let url = try url(
            pathComponents: ["conversations", conversationID.rawValue, "stream"]
        )
        let response = try await client.execute(
            HTTPClientRequest(url: url.absoluteString),
            deadline: .distantFuture,
            logger: logger
        )
        try validate(response)
        return GatewayConversationByteStream(bufferingPolicy: .bufferingOldest(16)) {
            continuation in
            let task = Task {
                do {
                    var pendingBytes: [UInt8] = []
                    for try await buffer in response.body {
                        pendingBytes.append(contentsOf: buffer.readableBytesView)
                        guard pendingBytes.count <= Self.maximumResponseBytes else {
                            throw CommunicatorWorldUpstreamError.streamFrameTooLarge
                        }
                        while let frameEnd = Self.sseFrameEnd(in: pendingBytes) {
                            let frame = Array(pendingBytes[...frameEnd])
                            pendingBytes.removeFirst(frameEnd + 1)
                            switch continuation.yield(ByteBuffer(bytes: frame)) {
                            case .enqueued:
                                break
                            case .dropped:
                                throw CommunicatorWorldUpstreamError.streamBufferOverflow
                            case .terminated:
                                return
                            @unknown default:
                                throw CommunicatorWorldUpstreamError.streamBufferOverflow
                            }
                        }
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
    }

    private static func sseFrameEnd(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 2 else { return nil }
        for index in 1..<bytes.count where bytes[index - 1] == 0x0A && bytes[index] == 0x0A {
            return index
        }
        return nil
    }

    private func execute(
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        method: HTTPMethod = .GET,
        body: Data? = nil
    ) async throws -> HTTPClientResponse {
        let url = try url(pathComponents: pathComponents, queryItems: queryItems)
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = method
        if let body {
            request.headers.add(name: "content-type", value: "application/json")
            request.body = .bytes(body)
        }
        return try await client.execute(request, timeout: .seconds(15), logger: logger)
    }

    private func url(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var url = baseURL
        for component in pathComponents {
            url.append(path: component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw CommunicatorWorldUpstreamError.invalidURL }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let result = components.url else {
            throw CommunicatorWorldUpstreamError.invalidURL
        }
        return result
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from response: HTTPClientResponse
    ) async throws -> Value {
        try validate(response)
        return try WorldJSON.makeDecoder().decode(type, from: await collect(response.body))
    }

    private func collect(_ body: HTTPClientResponse.Body) async throws -> Data {
        do {
            let buffer = try await body.collect(upTo: Self.maximumResponseBytes)
            return Data(buffer.readableBytesView)
        } catch is NIOTooManyBytesError {
            throw CommunicatorWorldUpstreamError.responseTooLarge
        }
    }

    private func validate(_ response: HTTPClientResponse) throws {
        guard (200..<300).contains(response.status.code) else {
            throw CommunicatorWorldUpstreamError.requestFailed(
                statusCode: UInt(response.status.code)
            )
        }
    }
}

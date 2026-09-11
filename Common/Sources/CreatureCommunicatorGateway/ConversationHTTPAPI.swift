import Foundation
import HTTPTypes
import Hummingbird
import ServiceLifecycle
import WorldCore

enum ConversationGatewayHTTPError: Error {
    case unsupportedMediaType
    case invalidQuery
    case conversationIdentityMismatch
}

public struct ConversationGatewayHTTPAPI: Sendable {
    public static let maximumBodyBytes = 1_048_576
    public static let maximumPageSize = 500
    public static let defaultPageSize = 100

    private let upstream: any CommunicatorWorldUpstream

    public init(upstream: any CommunicatorWorldUpstream) {
        self.upstream = upstream
    }

    public func addRoutes(to router: RouterGroup<BasicRequestContext>) {
        router.post("v1/conversations/:conversationID/utterances") { request, context in
            await respond {
                try requireJSON(request)
                let conversationID = try conversationID(from: context)
                let utterance = try await decode(PersonUtterance.self, from: request)
                guard utterance.conversationID == conversationID else {
                    throw ConversationGatewayHTTPError.conversationIdentityMismatch
                }
                let result = try await upstream.submit(utterance)
                return try jsonResponse(
                    result,
                    status: result.disposition == .accepted ? .accepted : .ok
                )
            }
        }

        router.get("v1/conversations/:conversationID/items") { request, context in
            await respond {
                let conversationID = try conversationID(from: context)
                let after = try request.uri.queryParameters["after_item_id"].map {
                    try ConversationItemID(validating: String($0))
                }
                let limit = try pageLimit(request)
                return try jsonResponse(
                    await upstream.items(in: conversationID, after: after, limit: limit)
                )
            }
        }

        router.get("v1/conversations/:conversationID/stream") { _, context in
            await respond {
                let conversationID = try conversationID(from: context)
                let stream = try await upstream.conversationStream(for: conversationID)
                var headers: HTTPFields = [
                    .contentType: "text/event-stream; charset=utf-8",
                    .cacheControl: "no-cache",
                ]
                headers[HTTPField.Name("x-accel-buffering")!] = "no"
                return Response(
                    status: .ok,
                    headers: headers,
                    body: ResponseBody { writer in
                        // A Communicator holds this stream open for as long as it is foregrounded.
                        // Graceful shutdown must cut it — cancelling the relay ends the upstream
                        // stream, whose termination cancels the World request — or a restart
                        // waits until the phone hangs up, or until systemd kills the process.
                        let relay = ConversationStreamRelay(stream)
                        await withGracefulShutdownHandler {
                            do {
                                for await buffer in relay.frames {
                                    try await writer.write(buffer)
                                }
                            } catch {
                                // Closing the response makes clients reconnect and recover.
                            }
                        } onGracefulShutdown: {
                            relay.cancel()
                        }
                        relay.cancel()
                        try? await writer.finish(nil)
                    }
                )
            }
        }
    }

    private func conversationID(from context: BasicRequestContext) throws -> ConversationID {
        guard let rawConversationID = context.parameters.get("conversationID") else {
            throw ConversationGatewayHTTPError.invalidQuery
        }
        return try ConversationID(validating: rawConversationID)
    }

    private func pageLimit(_ request: Request) throws -> Int {
        guard let rawLimit = request.uri.queryParameters["limit"] else {
            return Self.defaultPageSize
        }
        guard let limit = Int(rawLimit), (1...Self.maximumPageSize).contains(limit) else {
            throw ConversationGatewayHTTPError.invalidQuery
        }
        return limit
    }

    private func requireJSON(_ request: Request) throws {
        guard let contentType = request.headers[.contentType]?.lowercased(),
            contentType == "application/json" || contentType.hasPrefix("application/json;")
        else {
            throw ConversationGatewayHTTPError.unsupportedMediaType
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from request: Request
    ) async throws -> Value {
        let body = try await request.body.collect(upTo: Self.maximumBodyBytes)
        return try WorldJSON.makeDecoder().decode(type, from: body)
    }

    private func respond(_ operation: () async throws -> Response) async -> Response {
        do {
            return try await operation()
        } catch {
            return (try? errorResponse(for: error)) ?? Response(status: .internalServerError)
        }
    }

    private func errorResponse(for error: any Error) throws -> Response {
        let status: HTTPResponse.Status
        let code: String
        let message: String
        switch error {
        case ConversationGatewayHTTPError.unsupportedMediaType:
            status = .unsupportedMediaType
            code = "unsupported_media_type"
            message = "Content-Type must be application/json"
        case ConversationGatewayHTTPError.invalidQuery:
            status = .badRequest
            code = "invalid_query"
            message = "The conversation query is invalid"
        case ConversationGatewayHTTPError.conversationIdentityMismatch:
            status = .conflict
            code = "conversation_identity_mismatch"
            message = "The route and body conversation identifiers do not match"
        case let responseError as any HTTPResponseError
        where responseError.status == .contentTooLarge:
            status = .contentTooLarge
            code = "body_too_large"
            message = "The request body exceeds the allowed size"
        case is DecodingError, is WorldContractError, is WorldIdentifierError:
            status = .badRequest
            code = "invalid_request"
            message = "The conversation request is invalid"
        default:
            status = .serviceUnavailable
            code = "world_unavailable"
            message = "Creature World is temporarily unavailable"
        }
        return try jsonResponse(
            CommunicatorGatewayErrorResponse(error: code, message: message),
            status: status
        )
    }

    private func jsonResponse<Value: Encodable>(
        _ value: Value,
        status: HTTPResponse.Status = .ok
    ) throws -> Response {
        let data = try WorldJSON.makeEncoder().encode(value)
        return Response(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

/// Pumps the World SSE byte stream through a task that graceful shutdown can cancel, so the
/// response writer — which cannot cross a `@Sendable` boundary — simply sees its frames end.
private final class ConversationStreamRelay: Sendable {
    let frames: AsyncStream<ByteBuffer>
    private let task: Task<Void, Never>

    init(_ upstream: GatewayConversationByteStream) {
        let (frames, continuation) = AsyncStream<ByteBuffer>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        self.frames = frames
        task = Task {
            do {
                for try await buffer in upstream {
                    if case .terminated = continuation.yield(buffer) {
                        break
                    }
                }
            } catch {
                // Upstream failure ends the relay; the client reconnects and reconciles.
            }
            continuation.finish()
        }
        continuation.onTermination = { [task] _ in task.cancel() }
    }

    func cancel() {
        task.cancel()
    }
}

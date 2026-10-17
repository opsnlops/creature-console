import AsyncHTTPClient
import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import Testing
import Tracing

@testable import creature_world

/// #237: on 2026-10-16 Creature Server closed the World's connections before reading a
/// request, and every scene that hit one went quiet. The World now sends such a request again.
@Suite("A request dropped before it is read is sent again")
struct DroppedConnectionRetryTests {
    /// Closes the first `drops` connections the moment they open - as Creature Server did -
    /// then answers each request with a 200 and `{"ok":true}`.
    private final class DroppingServer: ChannelInboundHandler, Sendable {
        typealias InboundIn = ByteBuffer
        typealias OutboundOut = ByteBuffer

        let drops: Int
        let accepted = NIOLockedValueBox(0)

        init(drops: Int) { self.drops = drops }

        func channelActive(context: ChannelHandlerContext) {
            let number = accepted.withLockedValue { count -> Int in
                count += 1
                return count
            }
            if number <= drops { context.close(promise: nil) }
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let body = #"{"ok":true}"#
            let response =
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)"
                + "\r\nConnection: close\r\n\r\n\(body)"
            context.writeAndFlush(
                wrapOutboundOut(context.channel.allocator.buffer(string: response))
            ).whenComplete { _ in context.close(promise: nil) }
        }
    }

    private func serve(drops: Int) async throws -> (Channel, DroppingServer) {
        let handler = DroppingServer(drops: drops)
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        return (channel, handler)
    }

    private func request(port: Int) -> HTTPClientRequest {
        var request = HTTPClientRequest(
            url: "http://127.0.0.1:\(port)/api/v1/animation/dialog-stream/start")
        request.method = .POST
        request.body = .bytes(ByteBuffer(string: "{}"))
        return request
    }

    @Test("Two drops in a row, then the server reads it: the third send gets the answer")
    func retriesPastDroppedConnections() async throws {
        let (server, handler) = try await serve(drops: 2)
        defer { try? server.close().wait() }
        let client = HTTPClient(eventLoopGroupProvider: .singleton)
        defer { Task { try? await client.shutdown() } }
        let port = try #require(server.localAddress?.port)
        let response = try await withSpan("test") { span in
            try await CreatureServerConfiguration.execute(
                request(port: port), on: client, timeout: .seconds(5),
                logger: Logger(label: "retry-tests"), span: span)
        }
        #expect(response.status == .ok)
        #expect(handler.accepted.withLockedValue { $0 } == 3)
    }

    @Test("A server that keeps dropping is given up on after two more tries")
    func givesUpAfterTheRetries() async throws {
        let (server, handler) = try await serve(drops: 10)
        defer { try? server.close().wait() }
        let client = HTTPClient(eventLoopGroupProvider: .singleton)
        defer { Task { try? await client.shutdown() } }
        let port = try #require(server.localAddress?.port)
        await #expect(throws: (any Error).self) {
            try await withSpan("test") { span in
                _ = try await CreatureServerConfiguration.execute(
                    request(port: port), on: client, timeout: .seconds(5),
                    logger: Logger(label: "retry-tests"), span: span)
            }
        }
        // Every send was a connection of its own (the pool may open one more ahead).
        #expect(
            handler.accepted.withLockedValue { $0 }
                >= 1 + CreatureServerConfiguration.droppedConnectionRetries)
    }
}

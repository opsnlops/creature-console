import AsyncHTTPClient
import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import Testing
import Tracing

@testable import creature_world

#if canImport(Network)
    import Network
#endif

/// #237: on 2026-10-16 Creature Server closed the World's connections before reading a
/// request, and every scene that hit one went quiet. The World now sends such a request again.
@Suite("A request dropped before it is read is sent again")
struct DroppedConnectionRetryTests {
    /// Closes the first `drops` connections the moment they open - as Creature Server did -
    /// then answers each request with a 200 and `{"ok":true}`. With `dropAfterReading`, it
    /// takes every request in and closes that much later without answering, as a server that
    /// acted on it would.
    private final class DroppingServer: ChannelInboundHandler, Sendable {
        typealias InboundIn = ByteBuffer
        typealias OutboundOut = ByteBuffer

        let drops: Int
        let dropAfterReading: TimeAmount?
        let accepted = NIOLockedValueBox(0)

        init(drops: Int, dropAfterReading: TimeAmount? = nil) {
            self.drops = drops
            self.dropAfterReading = dropAfterReading
        }

        func channelActive(context: ChannelHandlerContext) {
            let number = accepted.withLockedValue { count -> Int in
                count += 1
                return count
            }
            if dropAfterReading == nil, number <= drops { context.close(promise: nil) }
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if let dropAfterReading {
                let channel = context.channel
                channel.eventLoop.scheduleTask(in: dropAfterReading) { channel.close(promise: nil) }
                return
            }
            let body = #"{"ok":true}"#
            let response =
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)"
                + "\r\nConnection: close\r\n\r\n\(body)"
            context.writeAndFlush(
                wrapOutboundOut(context.channel.allocator.buffer(string: response))
            ).whenComplete { _ in context.close(promise: nil) }
        }
    }

    private func serve(drops: Int, dropAfterReading: TimeAmount? = nil) async throws
        -> (Channel, DroppingServer)
    {
        let handler = DroppingServer(drops: drops, dropAfterReading: dropAfterReading)
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
            // This server never reads before it drops, so a slow machine's drop still counts
            // (#247): on the CI runner a fresh connection took longer than 50 ms to fail.
            try await CreatureServerConfiguration.execute(
                request(port: port), on: client, timeout: .seconds(5),
                logger: Logger(label: "retry-tests"), span: span, fastDrop: .seconds(5))
        }
        #expect(response.status == .ok)
        #expect(handler.accepted.withLockedValue { $0 } == 3)
    }

    @Test("A reset is a dropped connection however the client reports it; a refusal is not")
    func resetIsADrop() {
        #expect(
            CreatureServerConfiguration.isDroppedConnection(HTTPClientError.remoteConnectionClosed))
        #expect(CreatureServerConfiguration.isDroppedConnection(ChannelError.ioOnClosedChannel))
        #expect(
            CreatureServerConfiguration.isDroppedConnection(
                IOError(errnoCode: ECONNRESET, reason: "read")))
        #expect(
            !CreatureServerConfiguration.isDroppedConnection(
                IOError(errnoCode: ECONNREFUSED, reason: "connect")))
        #expect(!CreatureServerConfiguration.isDroppedConnection(HTTPClientError.readTimeout))
        #if canImport(Network)
            // Network.framework's own error, as the CI runner reported the reset (#247).
            #expect(CreatureServerConfiguration.isDroppedConnection(NWError.posix(.ECONNRESET)))
            #expect(!CreatureServerConfiguration.isDroppedConnection(NWError.posix(.ECONNREFUSED)))
        #endif
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
                    logger: Logger(label: "retry-tests"), span: span, fastDrop: .seconds(5))
            }
        }
        // Every send was a connection of its own (the pool may open one more ahead).
        #expect(
            handler.accepted.withLockedValue { $0 }
                >= 1 + CreatureServerConfiguration.droppedConnectionRetries)
    }

    @Test("A drop after the server could have read the request is never sent again")
    func slowDropIsNotResent() async throws {
        // Taken in, and dropped 200 ms later: four times the bound, on any machine.
        let (server, handler) = try await serve(drops: 0, dropAfterReading: .milliseconds(200))
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
        #expect(handler.accepted.withLockedValue { $0 } == 1)
    }
}

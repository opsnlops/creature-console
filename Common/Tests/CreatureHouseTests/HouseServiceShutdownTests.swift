import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import HummingbirdWebSocket
import Logging
import NIOCore
import ServiceLifecycleTestKit
import Testing
import WorldCore

@testable import creature_house

@Suite("The house stops when told")
struct HouseServiceShutdownTests {
    /// With scenes offered and without: either way the house follows what it should until it is
    /// told to stop, and then cuts it and stops. The clock starts at the stop, once everything
    /// is connected - connecting is not stopping, and on 2026-11-03 a CI runner stalled every
    /// test's first connection for four and a half seconds, this one's clock running (#277).
    @Test(
        "A house follows until told, then cuts Home Assistant and the world and stops promptly",
        .timeLimit(.minutes(1)), arguments: [true, false])
    func stopsPromptly(offersScenes: Bool) async throws {
        let (connected, connection) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let router = Router()
        // The scene list, and nothing else: the mappings below want no entities.
        router.get("api/states") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: "[]")))
        }
        // A world that takes what it is told, and whose stream stays open and says nothing.
        router.post("events") { _, _ in Response(status: .accepted) }
        router.get("stream") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "text/event-stream"],
                body: .init { writer in
                    try await writer.write(ByteBuffer(string: ": hello\n\n"))
                    connection.yield()
                    for await _ in released {}
                    try await writer.finish(nil)
                })
        }
        // A Home Assistant that authenticates, subscribes, and then says nothing forever.
        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade { _, _, _ in
                .upgrade([:]) { inbound, outbound, _ in
                    try await outbound.write(.text(#"{"type":"auth_required"}"#))
                    var messages = inbound.messages(maxSize: 1 << 20).makeAsyncIterator()
                    _ = try await messages.next()
                    try await outbound.write(.text(#"{"type":"auth_ok"}"#))
                    _ = try await messages.next()
                    try await outbound.write(.text(#"{"id":1,"type":"result","success":true}"#))
                    connection.yield()
                    while try await messages.next() != nil {}
                }
            },
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
        try await app.test(.live) { liveClient in
            defer { release.finish() }
            let port = try #require(liveClient.port)
            let outbox = FileManager.default.temporaryDirectory
                .appendingPathComponent("house-shutdown-\(UUID().uuidString).jsonl").path
            let server = URL(string: "http://localhost:\(port)")!
            let configuration = HouseConfiguration(
                homeAssistantURL: server,
                worldURL: server,
                houseID: try EntityID(validating: "house:test"),
                mappings: [],
                offersScenes: offersScenes,
                outboxPath: outbox)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            let service = HouseService(
                configuration: configuration, token: "t", client: client,
                logger: Logger(label: "house-shutdown-tests"))

            try await testGracefulShutdown { trigger in
                try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        try await service.run()
                        return "stopped"
                    }
                    group.addTask {
                        var waitingFor = offersScenes ? 2 : 1
                        for await _ in connected {
                            waitingFor -= 1
                            if waitingFor == 0 { return "following" }
                        }
                        return "gave up"
                    }
                    // The house is following before anyone tells it anything.
                    let first = try await group.next()
                    #expect(first == "following")
                    let told = ContinuousClock.now
                    trigger.triggerGracefulShutdown()
                    let second = try await group.next()
                    #expect(second == "stopped")
                    #expect(ContinuousClock.now - told < .seconds(3))
                    group.cancelAll()
                }
            }
        }
    }
}

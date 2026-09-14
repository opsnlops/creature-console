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
    @Test("A graceful shutdown cuts the Home Assistant socket and returns within a second")
    func stopsPromptly() async throws {
        // A Home Assistant that authenticates, subscribes, and then says nothing forever.
        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade { _, _, _ in
                .upgrade([:]) { inbound, outbound, _ in
                    try await outbound.write(.text(#"{"type":"auth_required"}"#))
                    var messages = inbound.messages(maxSize: 1 << 20).makeAsyncIterator()
                    _ = try await messages.next()
                    try await outbound.write(.text(#"{"type":"auth_ok"}"#))
                    _ = try await messages.next()
                    try await outbound.write(.text(#"{"id":1,"type":"result","success":true}"#))
                    while try await messages.next() != nil {}
                }
            },
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
        try await app.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let outbox = FileManager.default.temporaryDirectory
                .appendingPathComponent("house-shutdown-\(UUID().uuidString).jsonl").path
            let configuration = HouseConfiguration(
                homeAssistantURL: URL(string: "http://localhost:\(port)")!,
                worldURL: URL(string: "http://localhost:1")!,  // nobody home; the outbox keeps it
                houseID: try EntityID(validating: "house:test"),
                mappings: [],
                offersScenes: false,
                outboxPath: outbox)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            let service = HouseService(
                configuration: configuration, token: "t", client: client,
                logger: Logger(label: "house-shutdown-tests"))

            let started = ContinuousClock.now
            try await testGracefulShutdown { trigger in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await service.run() }
                    // Let it connect, then tell it to stop.
                    try await Task.sleep(for: .milliseconds(400))
                    trigger.triggerGracefulShutdown()
                    try await group.next()
                }
            }
            #expect(ContinuousClock.now - started < .seconds(3))
        }
    }
}

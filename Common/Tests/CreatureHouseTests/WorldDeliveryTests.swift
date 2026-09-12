import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_house

@Suite("Delivering the house to the world")
struct WorldDeliveryTests {
    @Test("Events reach the world in order; while it is away they wait on disk, then follow")
    func outboxSurvivesTheWorldBeingAway() async throws {
        let world = StubWorld()
        let outbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("house-outbox-\(UUID().uuidString).jsonl").path
        try await world.makeApplication().test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            let delivery = WorldDelivery(
                worldURL: URL(string: "http://localhost:\(port)/world/v1")!, client: client,
                outboxPath: outbox, logger: Logger(label: "delivery-tests"))

            await delivery.deliver(try makeEvent("first"))
            #expect(await delivery.pendingCount == 0)

            await world.setAvailable(false)
            await delivery.deliver(try makeEvent("second"))
            await delivery.deliver(try makeEvent("third"))
            #expect(await delivery.pendingCount == 2)
            // The outbox is on disk: a restarted adapter picks the same two up.
            let restarted = WorldDelivery(
                worldURL: URL(string: "http://localhost:\(port)/world/v1")!, client: client,
                outboxPath: outbox, logger: Logger(label: "delivery-tests"))
            #expect(await restarted.pendingCount == 2)

            await world.setAvailable(true)
            await restarted.flush()
            #expect(await restarted.pendingCount == 0)
            #expect(
                await world.received.map { $0.source.sourceEventID } == [
                    "first", "second", "third",
                ])
            #expect(
                try String(contentsOfFile: outbox, encoding: .utf8).isEmpty)
        }
    }

    private func makeEvent(_ key: String) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: HouseEvents.doorUnlocked,
            occurredAt: Date(timeIntervalSince1970: 1_789_600_000),
            source: EventSource(
                id: SourceID(validating: "home-assistant:lock-front-door"),
                kind: HouseEvents.sourceKind, sourceEventID: key),
            subjectIDs: [EntityID(validating: "place:front-door")],
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: [:]
        )
    }
}

private actor StubWorld {
    private(set) var received: [WorldEventEnvelope] = []
    private var available = true

    func setAvailable(_ value: Bool) { available = value }

    private func accept(_ event: WorldEventEnvelope) -> Bool {
        guard available else { return false }
        received.append(event)
        return true
    }

    nonisolated func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        router.post("world/v1/events") { request, _ in
            let body = try await request.body.collect(upTo: 1 << 20)
            let event = try WorldJSON.makeDecoder().decode(
                WorldEventEnvelope.self, from: Data(buffer: body))
            guard await self.accept(event) else {
                return Response(status: .serviceUnavailable)
            }
            return Response(
                status: .accepted, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: #"{"disposition":"accepted"}"#)))
        }
        return Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
    }
}

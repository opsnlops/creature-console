import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_world

@Suite("Streaming scene performer")
struct StreamingScenePerformerTests {
    private let home = try! EntityID(validating: "region:home")
    private let beaky = try! EntityID(validating: "character:beaky")
    private let mango = try! EntityID(validating: "character:mango")

    @Test(
        "A scene opens a dialog-stream session on the region's stage, sends turns as they land, and finishes"
    )
    func streamsTurnsThroughCreatureServer() async throws {
        let server = StubCreatureServer(startStatus: .ok)
        try await server.makeApplication().test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            let performer = makePerformer(port: port, client: client)
            var scene = try makeScene()

            await performer.sceneOpened(scene)
            let first = SceneTurn(
                characterID: beaky, responseID: .generated(), text: "Servos, I hope!",
                offeredAt: scene.openedAt, answeredAt: scene.openedAt)
            scene.turns.append(first)
            await performer.sceneTurn(scene, first)
            let second = SceneTurn(
                characterID: mango, responseID: .generated(), text: "Heat sinks.",
                offeredAt: scene.openedAt, answeredAt: scene.openedAt)
            scene.turns.append(second)
            await performer.sceneTurn(scene, second)
            let performance = try await performer.sceneClosed(scene)

            #expect(performance.state == .performed)
            #expect(performance.providerReference == "animation:stitched")
            let calls = await server.calls
            #expect(calls.map(\.path) == ["start", "turn", "turn", "finish"])
            #expect(calls[0].strings["stage_id"] == "stage:mainstage")
            #expect(calls[0].lists["creature_ids"] == ["creature-beaky", "creature-mango"])
            #expect(calls[1].strings["creature_id"] == "creature-beaky")
            #expect(calls[1].strings["text"] == "Servos, I hope!")
            #expect(calls[2].strings["creature_id"] == "creature-mango")
        }
    }

    @Test("When the server refuses the session, the scene falls back to the complete render")
    func fallsBackWhenStartIsRefused() async throws {
        let server = StubCreatureServer(startStatus: .conflict)
        try await server.makeApplication().test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            let performer = makePerformer(port: port, client: client)
            var scene = try makeScene()

            await performer.sceneOpened(scene)
            let turn = SceneTurn(
                characterID: beaky, responseID: .generated(), text: "Anyone?",
                offeredAt: scene.openedAt, answeredAt: scene.openedAt)
            scene.turns.append(turn)
            await performer.sceneTurn(scene, turn)
            let performance = try await performer.sceneClosed(scene)

            #expect(performance.state == .queued)
            #expect(performance.providerReference == "job:dialog")
            #expect(await server.calls.map(\.path) == ["start", "dialog"])
        }
    }

    @Test("A region with no stage skips streaming and renders the scene whole")
    func regionWithoutStageRendersWhole() async throws {
        let server = StubCreatureServer(startStatus: .ok)
        try await server.makeApplication().test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            let performer = makePerformer(port: port, client: client, regions: [:])
            var scene = try makeScene()
            await performer.sceneOpened(scene)
            let turn = SceneTurn(
                characterID: beaky, responseID: .generated(), text: "Hello.",
                offeredAt: scene.openedAt, answeredAt: scene.openedAt)
            scene.turns.append(turn)
            await performer.sceneTurn(scene, turn)

            _ = try await performer.sceneClosed(scene)

            #expect(await server.calls.map(\.path) == ["dialog"])
        }
    }

    private func makePerformer(
        port: Int, client: HTTPClient,
        regions: [EntityID: RegionConfiguration]? = nil
    ) -> StreamingScenePerformer {
        let configuration = CreatureServerConfiguration(
            url: URL(string: "http://localhost:\(port)")!, proxyHost: nil, apiKey: nil)
        let creatures = FixedCreatures(map: [beaky: "creature-beaky", mango: "creature-mango"])
        let clock = ManualWorldClock(now: Date(timeIntervalSince1970: 1_789_400_000))
        let logger = Logger(label: "streaming-scene-performer-tests")
        return StreamingScenePerformer(
            configuration: configuration,
            regions: regions ?? [home: RegionConfiguration(stageID: "stage:mainstage")],
            creatures: creatures,
            fallback: CreatureServerScenePerformer(
                configuration: configuration, creatures: creatures, client: client,
                clock: clock, logger: logger),
            client: client,
            clock: clock,
            logger: logger
        )
    }

    private func makeScene() throws -> Scene {
        try Scene(
            regionID: home,
            conversationID: ConversationID(validating: "conversation:april-house"),
            trigger: SceneTrigger(
                kind: .personUtterance, eventID: .generated(), text: "What is in the box?"),
            participants: [beaky, mango],
            openedAt: Date(timeIntervalSince1970: 1_789_400_000)
        )
    }
}

private struct FixedCreatures: CharacterCreatureResolving {
    let map: [EntityID: String]
    func creatureID(for characterID: EntityID) async throws -> String? { map[characterID] }
}

private actor StubCreatureServer {
    struct Call: Sendable {
        let path: String
        /// Top-level string and string-array fields of the JSON body.
        let strings: [String: String]
        let lists: [String: [String]]
    }

    private let startStatus: HTTPResponse.Status
    private(set) var calls: [Call] = []

    init(startStatus: HTTPResponse.Status) {
        self.startStatus = startStatus
    }

    private func record(_ path: String, _ body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        calls.append(
            Call(
                path: path,
                strings: json.compactMapValues { $0 as? String },
                lists: json.compactMapValues { $0 as? [String] }))
    }

    nonisolated func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        @Sendable func reply(_ status: HTTPResponse.Status, _ json: String) -> Response {
            Response(
                status: status, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: json)))
        }
        router.post("api/v1/animation/dialog-stream/start") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            await self.record("start", Data(buffer: body))
            let status = await self.startStatus
            return status == .ok
                ? reply(.ok, #"{"session_id":"session-1","status":"started"}"#)
                : reply(.conflict, #"{"code":409,"message":"Creature X is not registered"}"#)
        }
        router.post("api/v1/animation/dialog-stream/turn") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            await self.record("turn", Data(buffer: body))
            return reply(.ok, #"{"session_id":"session-1","status":"ok","turns_received":1}"#)
        }
        router.post("api/v1/animation/dialog-stream/finish") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            await self.record("finish", Data(buffer: body))
            return reply(
                .ok,
                #"{"session_id":"session-1","status":"completed","animation_id":"animation:stitched","playback_triggered":true,"exchange_status":"ready"}"#
            )
        }
        router.post("api/v1/animation/dialog") { request, _ in
            let body = try await request.body.collect(upTo: 65_536)
            await self.record("dialog", Data(buffer: body))
            return reply(
                .accepted, #"{"job_id":"job:dialog","job_type":"dialog","message":"queued"}"#)
        }
        return Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
    }
}

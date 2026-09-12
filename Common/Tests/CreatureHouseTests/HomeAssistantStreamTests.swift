import AsyncHTTPClient
import Foundation
import Hummingbird
import HummingbirdTesting
import HummingbirdWebSocket
import Logging
import NIOCore
import Testing
import WorldCore

@testable import creature_house

@Suite("Home Assistant, over the wire")
struct HomeAssistantStreamTests {
    @Test("Authenticate, subscribe, and hear a state change; a bad token is refused")
    func followsStateChanges() async throws {
        let received = Received()
        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade { _, _, _ in
                .upgrade([:]) { inbound, outbound, _ in
                    try await outbound.write(
                        .text(#"{"type":"auth_required","ha_version":"2026.9.2"}"#))
                    var messages = inbound.messages(maxSize: 1 << 20).makeAsyncIterator()
                    guard case .text(let auth)? = try await messages.next() else { return }
                    guard auth.contains(#""access_token":"good-token""#) else {
                        try await outbound.write(
                            .text(#"{"type":"auth_invalid","message":"Invalid access token"}"#))
                        return
                    }
                    try await outbound.write(.text(#"{"type":"auth_ok","ha_version":"2026.9.2"}"#))
                    guard case .text(let subscribe)? = try await messages.next(),
                        subscribe.contains("subscribe_events")
                    else { return }
                    try await outbound.write(
                        .text(#"{"id":1,"type":"result","success":true,"result":null}"#))
                    try await outbound.write(
                        .text(
                            #"{"id":1,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"lock.front_door","old_state":{"entity_id":"lock.front_door","state":"locked","attributes":{},"last_changed":"2026-09-12T20:00:00.000000+00:00"},"new_state":{"entity_id":"lock.front_door","state":"unlocked","attributes":{"friendly_name":"Front Door"},"last_changed":"2026-09-12T20:41:10.123456+00:00"}},"context":{"id":"01J8CTX"}}}"#
                        ))
                    // Keep the socket open until the client has seen the event.
                    try await Task.sleep(for: .milliseconds(200))
                }
            },
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )
        try await app.test(.live) { client in
            let port = try #require(client.port)
            let good = HomeAssistantStream(
                baseURL: URL(string: "http://localhost:\(port)")!, token: "good-token",
                logger: Logger(label: "ha-tests"))
            #expect(good.webSocketURL == "ws://localhost:\(port)/api/websocket")
            do {
                try await good.follow { old, new in await received.record(old, new) }
            } catch HomeAssistantError.streamEnded {
                // The stub closes after one event; a real server never does.
            }
            let changes = await received.changes
            #expect(changes.count == 1)
            #expect(changes.first?.new.entityID == "lock.front_door")
            #expect(changes.first?.new.state == "unlocked")
            #expect(changes.first?.new.contextID == "01J8CTX")
            #expect(changes.first?.old?.state == "locked")
            // Fractional seconds survive: 2026-09-12T20:41:10.123456Z.
            let changed = try #require(changes.first?.new.lastChanged)
            #expect(abs(changed.timeIntervalSince1970 - 1_789_245_670.123456) < 0.001)
            #expect(changes.first?.new.attributes["friendly_name"] == .string("Front Door"))

            let bad = HomeAssistantStream(
                baseURL: URL(string: "http://localhost:\(port)")!, token: "wrong",
                logger: Logger(label: "ha-tests"))
            await #expect(throws: HomeAssistantError.self) {
                try await bad.follow { _, _ in }
            }
        }
    }

    @Test("The snapshot reads each mapped entity; the scene list comes by friendly name")
    func restReads() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.get("api/states/lock.front_door") { _, _ in
            #"{"entity_id":"lock.front_door","state":"locked","attributes":{},"last_changed":"2026-09-12T20:00:00+00:00"}"#
        }
        router.get("api/states/sensor.missing") { _, _ in Response(status: .notFound) }
        router.get("api/states") { _, _ in
            #"[{"entity_id":"scene.normal_evening","state":"unknown","attributes":{"friendly_name":"Normal Evening"},"last_changed":"2026-09-12T20:00:00+00:00"},{"entity_id":"light.kitchen","state":"on","attributes":{"friendly_name":"Kitchen"},"last_changed":"2026-09-12T20:00:00+00:00"},{"entity_id":"scene.bedtime","state":"unknown","attributes":{"friendly_name":"Bedtime"},"last_changed":"2026-09-12T20:00:00+00:00"}]"#
        }
        let activated = Received()
        router.post("api/services/scene/turn_on") { request, _ in
            let body = try await request.body.collect(upTo: 4_096)
            await activated.note(String(buffer: body))
            #expect(request.headers[.authorization] == "Bearer good-token")
            return "[]"
        }
        let app = Application(
            router: router, configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        try await app.test(.live) { liveClient in
            let port = try #require(liveClient.port)
            let client = HTTPClient(eventLoopGroupProvider: .singleton)
            defer { Task { try? await client.shutdown() } }
            let stream = HomeAssistantStream(
                baseURL: URL(string: "http://localhost:\(port)")!, token: "good-token",
                logger: Logger(label: "ha-tests"))

            let states = try await stream.states(
                of: ["lock.front_door", "sensor.missing"], client: client)
            #expect(states.map(\.entityID) == ["lock.front_door"])

            let scenes = try await stream.scenes(client: client)
            #expect(
                scenes == [
                    .init(entityID: "scene.bedtime", name: "Bedtime"),
                    .init(entityID: "scene.normal_evening", name: "Normal Evening"),
                ])
            try await stream.activate(scenes[1], client: client)
            #expect(await activated.notes == [#"{"entity_id":"scene.normal_evening"}"#])
        }
    }
}

actor Received {
    private(set) var changes: [(old: EntityState?, new: EntityState)] = []
    private(set) var notes: [String] = []
    func record(_ old: EntityState?, _ new: EntityState) { changes.append((old, new)) }
    func note(_ text: String) { notes.append(text) }
}

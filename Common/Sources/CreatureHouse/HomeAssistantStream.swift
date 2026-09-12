import AsyncHTTPClient
import Foundation
import HummingbirdWSClient
import Logging
import NIOCore
import WorldCore

/// Home Assistant, over its WebSocket API: authenticate, subscribe to `state_changed`, and
/// deliver each change; plus a REST read of the mapped entities for the startup snapshot and
/// the scene list, and `scene.turn_on` for the house's other arm.
///
/// Protocol: the server opens with `auth_required`; the client sends `auth` with the token;
/// `auth_ok` (or `auth_invalid`); then `subscribe_events` gets a `result` and, forever after,
/// `event` messages.
struct HomeAssistantStream: Sendable {
    let baseURL: URL
    let token: String
    let logger: Logger

    var webSocketURL: String {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        return components.url!.absoluteString
    }

    /// Follow state changes until the connection ends; the caller reconnects.
    func follow(_ onChange: @escaping @Sendable (EntityState?, EntityState) async -> Void)
        async throws
    {
        let token = self.token
        let logger = self.logger
        var configuration = WebSocketClientConfiguration()
        configuration.maxFrameSize = 1 << 20  // a `state_changed` for a busy entity is large
        configuration.autoPing = .enabled(timePeriod: .seconds(30))
        _ = try await WebSocketClient.connect(
            url: webSocketURL, configuration: configuration, logger: logger
        ) { inbound, outbound, _ in
            var authenticated = false
            var subscribed = false
            for try await frame in inbound.messages(maxSize: 1 << 20) {
                guard case .text(let text) = frame,
                    let data = text.data(using: .utf8),
                    let message = try? JSONDecoder().decode(Message.self, from: data)
                else { continue }
                switch message.type {
                case "auth_required":
                    try await outbound.write(.text(#"{"type":"auth","access_token":"\#(token)"}"#))
                case "auth_ok":
                    authenticated = true
                    try await outbound.write(
                        .text(#"{"id":1,"type":"subscribe_events","event_type":"state_changed"}"#))
                case "auth_invalid":
                    throw HomeAssistantError.authenticationRefused(message.message ?? "")
                case "result":
                    guard authenticated else { continue }
                    if message.success == true {
                        subscribed = true
                        logger.info("Following Home Assistant state changes")
                    } else {
                        throw HomeAssistantError.subscriptionRefused(
                            message.error?.message ?? "")
                    }
                case "event":
                    guard subscribed, let change = message.event?.data,
                        let new = change.newState?.entityState(
                            contextID: message.event?.context?.id)
                    else { continue }
                    await onChange(change.oldState?.entityState(contextID: nil), new)
                default:
                    continue
                }
            }
            throw HomeAssistantError.streamEnded
        }
    }

    // MARK: - REST

    /// The current state of each mapped entity, for the startup snapshot.
    func states(of entityIDs: [String], client: HTTPClient) async throws -> [EntityState] {
        var states: [EntityState] = []
        for entityID in entityIDs {
            var request = HTTPClientRequest(
                url: baseURL.appendingPathComponent("api/states/\(entityID)").absoluteString)
            request.headers.add(name: "authorization", value: "Bearer \(token)")
            let response = try await client.execute(request, timeout: .seconds(15))
            guard response.status == .ok else {
                logger.warning(
                    "Home Assistant has no such entity",
                    metadata: ["entity_id": "\(entityID)", "status": "\(response.status.code)"])
                continue
            }
            let body = try await response.body.collect(upTo: 1 << 20)
            let raw = try JSONDecoder().decode(RawState.self, from: Data(body.readableBytesView))
            if let state = raw.entityState(contextID: nil) {
                states.append(state)
            }
        }
        return states
    }

    /// The scenes Home Assistant offers, by friendly name, with the entity to turn each on.
    func scenes(client: HTTPClient) async throws -> [Scene] {
        var request = HTTPClientRequest(
            url: baseURL.appendingPathComponent("api/states").absoluteString)
        request.headers.add(name: "authorization", value: "Bearer \(token)")
        let response = try await client.execute(request, timeout: .seconds(30))
        guard response.status == .ok else {
            throw HomeAssistantError.unexpectedStatus(UInt(response.status.code))
        }
        let body = try await response.body.collect(upTo: 64 << 20)
        return try JSONDecoder().decode([RawState].self, from: Data(body.readableBytesView))
            .filter { $0.entityID.hasPrefix("scene.") }
            .compactMap { raw in
                guard case .string(let name)? = raw.attributes["friendly_name"] else { return nil }
                return Scene(entityID: raw.entityID, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    /// Set a scene.
    func activate(_ scene: Scene, client: HTTPClient) async throws {
        var request = HTTPClientRequest(
            url: baseURL.appendingPathComponent("api/services/scene/turn_on").absoluteString)
        request.method = .POST
        request.headers.add(name: "authorization", value: "Bearer \(token)")
        request.headers.add(name: "content-type", value: "application/json")
        request.body = .bytes(
            try JSONEncoder().encode(["entity_id": scene.entityID]))
        let response = try await client.execute(request, timeout: .seconds(15))
        guard response.status == .ok else {
            throw HomeAssistantError.unexpectedStatus(UInt(response.status.code))
        }
    }

    struct Scene: Equatable, Sendable {
        let entityID: String
        let name: String
    }

    // MARK: - Wire

    private struct Message: Decodable {
        struct Error: Decodable { let message: String? }
        struct Event: Decodable {
            struct Context: Decodable { let id: String? }
            struct Data: Decodable {
                let entityID: String?
                let oldState: RawState?
                let newState: RawState?
                private enum CodingKeys: String, CodingKey {
                    case entityID = "entity_id"
                    case oldState = "old_state"
                    case newState = "new_state"
                }
            }
            let eventType: String?
            let data: Data?
            let context: Context?
            private enum CodingKeys: String, CodingKey {
                case eventType = "event_type"
                case data, context
            }
        }
        let type: String
        let message: String?
        let success: Bool?
        let error: Error?
        let event: Event?
    }

    struct RawState: Decodable {
        let entityID: String
        let state: String
        let attributes: [String: WorldJSONValue]
        let lastChanged: String
        private enum CodingKeys: String, CodingKey {
            case entityID = "entity_id"
            case state, attributes
            case lastChanged = "last_changed"
        }

        func entityState(contextID: String?) -> EntityState? {
            guard let changed = Self.parse(lastChanged) else { return nil }
            return EntityState(
                entityID: entityID, state: state, attributes: attributes, lastChanged: changed,
                contextID: contextID)
        }

        private static func parse(_ timestamp: String) -> Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: timestamp) { return date }
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            return whole.date(from: timestamp)
        }
    }
}

enum HomeAssistantError: Error, LocalizedError {
    case authenticationRefused(String)
    case subscriptionRefused(String)
    case streamEnded
    case unexpectedStatus(UInt)

    var errorDescription: String? {
        switch self {
        case .authenticationRefused(let message): "Home Assistant refused the token: \(message)"
        case .subscriptionRefused(let message):
            "Home Assistant refused the subscription: \(message)"
        case .streamEnded: "Home Assistant closed the stream"
        case .unexpectedStatus(let code): "Home Assistant answered HTTP \(code)"
        }
    }
}

import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import Tracing
import WorldCore

/// Where the world turns a finished scene into voices and motion.
struct CreatureServerConfiguration: Codable, Equatable, Sendable {
    /// Base URL of Creature Server, e.g. `https://server.prod.chirpchirp.dev`.
    var url: URL
    var proxyHost: String?
    var apiKey: String?

    private enum CodingKeys: String, CodingKey {
        case url
        case proxyHost = "proxy_host"
        case apiKey = "api_key"
    }
}

/// Which creature each character speaks through, for a scene render.
protocol CharacterCreatureResolving: Sendable {
    func creatureID(for characterID: EntityID) async throws -> String?
}

/// Until a Creature Server is configured, a scene with words cannot be performed; it is recorded
/// as failed so it is visible in the Viewer rather than silently dropped.
struct NotConnectedScenePerformer: ScenePerforming, Sendable {
    static let errorCode = "creature_server_not_configured"
    let clock: any WorldClock

    func perform(_ scene: Scene) async throws -> ScenePerformance {
        ScenePerformance(state: .failed, errorCode: Self.errorCode, occurredAt: await clock.now)
    }
}

/// Creature Server's ad-hoc dialog pipeline: the complete scene rendered as one jointly
/// conditioned performance (ElevenLabs Text-to-Dialogue), autoplayed, kept in the server's
/// TTL collection so it never clutters the animation library.
struct CreatureServerScenePerformer: ScenePerforming, Sendable {
    static let requestFailedCode = "creature_server_dialog_refused"
    static let unreachableCode = "creature_server_unreachable"
    static let noCreatureCode = "character_has_no_creature"

    private let configuration: CreatureServerConfiguration
    private let creatures: any CharacterCreatureResolving
    private let client: HTTPClient
    private let clock: any WorldClock
    private let logger: Logger

    init(
        configuration: CreatureServerConfiguration,
        creatures: any CharacterCreatureResolving,
        client: HTTPClient,
        clock: any WorldClock,
        logger: Logger
    ) {
        self.configuration = configuration
        self.creatures = creatures
        self.client = client
        self.clock = clock
        self.logger = logger
    }

    func perform(_ scene: Scene) async throws -> ScenePerformance {
        try await withSpan("creature.server.dialog", ofKind: .client) { span in
            span.attributes["scene.id"] = scene.sceneID.rawValue
            span.attributes["scene.turns"] = scene.spokenTurns.count
            var turns: [[String: Any]] = []
            for turn in scene.spokenTurns {
                guard let creatureID = try await creatures.creatureID(for: turn.characterID) else {
                    logger.warning(
                        "A character in the scene has no creature to speak through",
                        metadata: ["agent.character_id": "\(turn.characterID.rawValue)"])
                    return ScenePerformance(
                        state: .failed, errorCode: Self.noCreatureCode, occurredAt: await clock.now)
                }
                turns.append(["creature_id": creatureID, "text": turn.text ?? ""])
            }
            let body: [String: Any] = [
                "turns": turns,
                "persistence": "adhoc",
                "autoplay": true,
                "title": "Scene \(scene.sceneID.rawValue)",
            ]
            var request = HTTPClientRequest(
                url: configuration.url.appending(path: "api/v1/animation/dialog").absoluteString)
            request.method = .POST
            request.headers.add(name: "content-type", value: "application/json")
            if let apiKey = configuration.apiKey {
                request.headers.add(name: "x-acw-api-key", value: apiKey)
            }
            if let proxyHost = configuration.proxyHost, let host = configuration.url.host() {
                request.headers.add(name: "host", value: host)
                request.url = request.url.replacingOccurrences(of: host, with: proxyHost)
            }
            request.body = .bytes(try JSONSerialization.data(withJSONObject: body))
            let now = await clock.now
            do {
                let response = try await client.execute(
                    request, timeout: .seconds(30), logger: logger)
                let data = Data(try await response.body.collect(upTo: 1_048_576).readableBytesView)
                span.attributes["http.response.status_code"] = Int(response.status.code)
                guard (200..<300).contains(response.status.code) else {
                    logger.error(
                        "Creature Server refused the scene",
                        metadata: [
                            "http.status": "\(response.status.code)",
                            "body": "\(String(decoding: data.prefix(500), as: UTF8.self))",
                        ])
                    return ScenePerformance(
                        state: .failed, errorCode: Self.requestFailedCode, occurredAt: now)
                }
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let jobID = json?["job_id"] as? String
                span.attributes["job.id"] = jobID ?? "unknown"
                // The render is an asynchronous job the server autoplays when done.
                return ScenePerformance(state: .queued, providerReference: jobID, occurredAt: now)
            } catch {
                span.recordError(error)
                logger.error(
                    "Creature Server could not be reached for the scene",
                    metadata: ["error": "\(error)"])
                return ScenePerformance(
                    state: .failed, errorCode: Self.unreachableCode, occurredAt: now)
            }
        }
    }
}

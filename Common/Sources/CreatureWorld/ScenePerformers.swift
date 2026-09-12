import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import Tracing
import WorldCore

/// Where the world turns a scene into voices and motion.
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

/// How a scene reaches the room.
enum ScenePerformanceMode: String, Codable, Equatable, Sendable {
    /// Each turn plays ~2 s after it is composed (`dialog-stream`), single-voice renders.
    case streaming
    /// The whole scene is rendered once it closes (`dialog`), jointly conditioned voices.
    case complete
}

/// What the world knows about a region that Creature Server needs: the stage the characters
/// are placed on, so they can look at each other.
struct RegionConfiguration: Codable, Equatable, Sendable {
    var stageID: String
    /// The places whose facts the characters in this region are told about: the doors, the
    /// rooms with motion sensors, the outside — and the house itself (`house:<name>`).
    var places: [EntityID]

    init(stageID: String, places: [EntityID] = []) {
        self.stageID = stageID
        self.places = places
    }

    private enum CodingKeys: String, CodingKey {
        case stageID = "stage_id"
        case places
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stageID = try container.decode(String.self, forKey: .stageID)
        places =
            try container.decodeIfPresent([String].self, forKey: .places)?
            .map(EntityID.init(validating:)) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stageID, forKey: .stageID)
        try container.encode(places.map(\.rawValue), forKey: .places)
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

    func sceneOpened(_ scene: Scene) async {}
    func sceneTurn(_ scene: Scene, _ turn: SceneTurn, streamed: Bool) async {}

    func sceneClosed(_ scene: Scene) async throws -> ScenePerformance {
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

    func sceneOpened(_ scene: Scene) async {}
    func sceneTurn(_ scene: Scene, _ turn: SceneTurn, streamed: Bool) async {}

    func sceneClosed(_ scene: Scene) async throws -> ScenePerformance {
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
            let request = try configuration.request(path: "api/v1/animation/dialog", body: body)
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

extension CreatureServerConfiguration {
    /// A JSON POST to Creature Server, through the proxy when one is configured.
    func request(path: String, body: [String: Any]) throws -> HTTPClientRequest {
        var request = HTTPClientRequest(url: url.appending(path: path).absoluteString)
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/json")
        if let apiKey {
            request.headers.add(name: "x-acw-api-key", value: apiKey)
        }
        if let proxyHost, let host = url.host() {
            request.headers.add(name: "host", value: host)
            request.url = request.url.replacingOccurrences(of: host, with: proxyHost)
        }
        request.body = .bytes(try JSONSerialization.data(withJSONObject: body))
        return request
    }
}

/// Creature Server's `dialog-stream` (3.46.0): a session per scene, opened when the scene opens
/// on the stage the region maps to; every spoken turn is sent the moment it is composed and
/// plays ~2 s later while the scene is still being composed; `finish` waits for the last turn
/// to play and stitches the exchange into one ad-hoc animation. When a session cannot be
/// opened (a bird's controller offline, no stage for the region) the scene falls back to the
/// complete-scene render at the end, so it is still heard.
actor StreamingScenePerformer: ScenePerforming {
    static let noStageCode = "region_has_no_stage"

    private let configuration: CreatureServerConfiguration
    private let regions: [EntityID: RegionConfiguration]
    private let creatures: any CharacterCreatureResolving
    private let fallback: any ScenePerforming
    private let client: HTTPClient
    private let clock: any WorldClock
    private let logger: Logger
    private var sessions: [SceneID: String] = [:]

    init(
        configuration: CreatureServerConfiguration,
        regions: [EntityID: RegionConfiguration],
        creatures: any CharacterCreatureResolving,
        fallback: any ScenePerforming,
        client: HTTPClient,
        clock: any WorldClock,
        logger: Logger
    ) {
        self.configuration = configuration
        self.regions = regions
        self.creatures = creatures
        self.fallback = fallback
        self.client = client
        self.clock = clock
        self.logger = logger
    }

    func sceneOpened(_ scene: Scene) async {
        await withSpan("creature.server.dialog_stream.start", ofKind: .client) { span in
            span.attributes["scene.id"] = scene.sceneID.rawValue
            guard let region = regions[scene.regionID] else {
                logger.warning(
                    "No stage is mapped for this region; the scene will be rendered whole at the end",
                    metadata: ["world.region_id": "\(scene.regionID.rawValue)"])
                span.attributes["error.type"] = Self.noStageCode
                return
            }
            var creatureIDs: [String] = []
            for participant in scene.participants {
                guard let creatureID = try? await creatures.creatureID(for: participant) else {
                    logger.warning(
                        "A participant has no creature; the scene will be rendered whole at the end",
                        metadata: ["agent.character_id": "\(participant.rawValue)"])
                    return
                }
                creatureIDs.append(creatureID)
            }
            do {
                let request = try configuration.request(
                    path: "api/v1/animation/dialog-stream/start",
                    body: [
                        "creature_ids": creatureIDs, "stage_id": region.stageID,
                        "resume_playlist": true,
                    ])
                let response = try await client.execute(
                    request, timeout: .seconds(15), logger: logger)
                let data = Data(try await response.body.collect(upTo: 65_536).readableBytesView)
                span.attributes["http.response.status_code"] = Int(response.status.code)
                guard response.status.code == 200,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let sessionID = json["session_id"] as? String
                else {
                    logger.warning(
                        "Creature Server would not open a dialog stream; the scene will be rendered whole at the end",
                        metadata: [
                            "http.status": "\(response.status.code)",
                            "body": "\(String(decoding: data.prefix(300), as: UTF8.self))",
                        ])
                    return
                }
                sessions[scene.sceneID] = sessionID
                span.attributes["streaming.session_id"] = sessionID
            } catch {
                span.recordError(error)
                logger.warning(
                    "Creature Server could not be reached to open a dialog stream",
                    metadata: ["error": "\(error)"])
            }
        }
    }

    /// A sentence of a line still being composed goes to the room the moment it lands; the
    /// server queues turns per creature in arrival order (creature-server#192 will let it
    /// keep the pose and prosody across them).
    func sceneTurnPiece(_ scene: Scene, character: EntityID, responseID: ResponseID, text: String)
        async
    {
        await speak(scene, character: character, text: text, piece: true)
    }

    /// A whole line — unless it was streamed, in which case the room has already heard it.
    func sceneTurn(_ scene: Scene, _ turn: SceneTurn, streamed: Bool) async {
        guard !streamed, let text = turn.text else { return }
        await speak(scene, character: turn.characterID, text: text, piece: false)
    }

    private func speak(_ scene: Scene, character: EntityID, text: String, piece: Bool) async {
        guard let sessionID = sessions[scene.sceneID] else { return }
        await withSpan("creature.server.dialog_stream.turn", ofKind: .client) { span in
            span.attributes["scene.id"] = scene.sceneID.rawValue
            span.attributes["streaming.session_id"] = sessionID
            span.attributes["agent.character_id"] = character.rawValue
            span.attributes["scene.turn.piece"] = piece
            guard let creatureID = try? await creatures.creatureID(for: character) else {
                return
            }
            do {
                let request = try configuration.request(
                    path: "api/v1/animation/dialog-stream/turn",
                    body: ["session_id": sessionID, "creature_id": creatureID, "text": text])
                let response = try await client.execute(
                    request, timeout: .seconds(15), logger: logger)
                span.attributes["http.response.status_code"] = Int(response.status.code)
                if response.status.code != 200 {
                    let data = Data(try await response.body.collect(upTo: 65_536).readableBytesView)
                    logger.error(
                        "Creature Server dropped a scene turn",
                        metadata: [
                            "http.status": "\(response.status.code)",
                            "body": "\(String(decoding: data.prefix(300), as: UTF8.self))",
                        ])
                }
            } catch {
                span.recordError(error)
                logger.error(
                    "Creature Server could not be reached for a scene turn",
                    metadata: ["error": "\(error)"])
            }
        }
    }

    func sceneClosed(_ scene: Scene) async throws -> ScenePerformance {
        guard let sessionID = sessions.removeValue(forKey: scene.sceneID) else {
            return try await fallback.sceneClosed(scene)
        }
        return await withSpan("creature.server.dialog_stream.finish", ofKind: .client) { span in
            span.attributes["scene.id"] = scene.sceneID.rawValue
            span.attributes["streaming.session_id"] = sessionID
            let now = await clock.now
            do {
                let request = try configuration.request(
                    path: "api/v1/animation/dialog-stream/finish", body: ["session_id": sessionID])
                // Finish blocks until the last turn has played.
                let response = try await client.execute(
                    request, timeout: .seconds(300), logger: logger)
                let data = Data(try await response.body.collect(upTo: 65_536).readableBytesView)
                span.attributes["http.response.status_code"] = Int(response.status.code)
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard response.status.code == 200 else {
                    logger.error(
                        "Creature Server could not finish the scene",
                        metadata: [
                            "http.status": "\(response.status.code)",
                            "body": "\(String(decoding: data.prefix(300), as: UTF8.self))",
                        ])
                    return ScenePerformance(
                        state: .failed, errorCode: CreatureServerScenePerformer.requestFailedCode,
                        occurredAt: now)
                }
                let animationID = json?["animation_id"] as? String
                let played = json?["playback_triggered"] as? Bool ?? false
                let exchange = json?["exchange_status"] as? String ?? "unknown"
                span.attributes["speech.animation_id"] = animationID ?? ""
                span.attributes["scene.exchange_status"] = exchange
                return ScenePerformance(
                    state: played ? .performed : .failed,
                    providerReference: (animationID?.isEmpty == false) ? animationID : sessionID,
                    errorCode: played ? nil : "dialog_stream_\(exchange)",
                    occurredAt: await clock.now)
            } catch {
                span.recordError(error)
                return ScenePerformance(
                    state: .failed, errorCode: CreatureServerScenePerformer.unreachableCode,
                    occurredAt: now)
            }
        }
    }
}

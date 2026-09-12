import AsyncHTTPClient
import Foundation
import Logging
import Metrics
import NIOCore
import Tracing
import WorldCore

/// What the world did with a turn Beaky wanted to say.
enum WorldResponseOutcome: Equatable, Sendable {
    /// The world carried the turn; delivery was decided and recorded.
    case accepted(CharacterDeliveryOutcome)
    /// The world had already carried a turn with this response identity.
    case duplicate(CharacterDeliveryOutcome)
    /// The world refused the turn for good; retrying the same intent would not help.
    case rejected(code: String, message: String)
}

enum WorldResponderError: Error, Equatable {
    case unavailable(status: UInt)
    /// The world refused for good (4xx); retrying the same request would not help.
    case rejected(code: String, message: String)
}

/// Something that can ask the world where a turn should be performed, before the words exist.
protocol WorldStaging: Sendable {
    func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) async throws -> CharacterStageResult
}

/// Something that can carry Beaky's turn to the world — routed by the world, or performed by
/// the mind on a stage the world decided.
protocol WorldTurnResponding: WorldStaging {
    func submit(_ intent: CharacterUtteranceIntent) async throws -> WorldResponseOutcome
    func record(_ performance: CharacterPerformance) async throws -> WorldResponseOutcome
}

/// Carries a `CharacterUtteranceIntent` to Creature World and reads back what happened.
///
/// A 5xx or transport failure throws so the caller can retry from the cursor; a 4xx is a
/// rejection the caller must record and move past — most importantly the identity conflict a
/// replayed consideration produces when the model phrased its answer differently the second time.
struct WorldResponder: WorldTurnResponding {
    private let client: HTTPClient
    private let worldURL: URL
    private let logger: Logger
    private let outcomeCounter = Counter(label: "creature_agent.world.responses")

    init(client: HTTPClient, worldURL: URL, logger: Logger) {
        self.client = client
        self.worldURL = worldURL
        self.logger = logger
    }

    func stage(
        _ stageRequest: CharacterStageRequest,
        in conversationID: ConversationID
    ) async throws -> CharacterStageResult {
        try await withSpan("creature.world.stage", ofKind: .client) { span in
            span.attributes["conversation.id"] = conversationID.rawValue
            span.attributes["conversation.response.id"] = stageRequest.responseID.rawValue
            let (status, body) = try await post(
                stageRequest, to: conversationID, route: "stage", span: span)
            guard status == 200 else {
                throw Self.failure(status: status, body: body)
            }
            let result = try WorldJSON.makeDecoder().decode(CharacterStageResult.self, from: body)
            span.attributes["conversation.stage.disposition"] = result.disposition.rawValue
            span.attributes["conversation.delivery.route"] = result.decision.route.rawValue
            span.attributes["conversation.delivery.reason"] = result.decision.reason.rawValue
            return result
        }
    }

    func submit(_ intent: CharacterUtteranceIntent) async throws -> WorldResponseOutcome {
        try await withSpan("creature.world.respond", ofKind: .client) { span in
            span.attributes["conversation.id"] = intent.conversationID.rawValue
            span.attributes["conversation.response.id"] = intent.responseID.rawValue
            let (status, body) = try await post(
                intent, to: intent.conversationID, route: "responses", span: span)
            return try outcome(status: status, body: body, span: span)
        }
    }

    func record(_ performance: CharacterPerformance) async throws -> WorldResponseOutcome {
        try await withSpan("creature.world.perform", ofKind: .client) { span in
            let intent = performance.intent
            span.attributes["conversation.id"] = intent.conversationID.rawValue
            span.attributes["conversation.response.id"] = intent.responseID.rawValue
            span.attributes["conversation.delivery.attempt.id"] = performance.attemptID.rawValue
            span.attributes["conversation.delivery.state"] = performance.outcome.state.rawValue
            let (status, body) = try await post(
                performance, to: intent.conversationID, route: "performances", span: span)
            return try outcome(status: status, body: body, span: span)
        }
    }

    private func post<Body: Encodable>(
        _ payload: Body,
        to conversationID: ConversationID,
        route: String,
        span: any Span
    ) async throws -> (status: UInt, body: Data) {
        try await post(
            payload,
            path: ["conversations", conversationID.rawValue, route],
            span: span
        )
    }

    private func post<Body: Encodable>(
        _ payload: Body,
        path: [String],
        span: any Span
    ) async throws -> (status: UInt, body: Data) {
        var url = worldURL
        for component in path {
            url.append(path: component)
        }
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/json")
        request.body = .bytes(try WorldJSON.makeEncoder().encode(payload))
        let response = try await client.execute(request, timeout: .seconds(15), logger: logger)
        // NIOCore's readableBytesView works on Linux, where ByteBuffer has no Data bridge.
        let body = Data(try await response.body.collect(upTo: 1_048_576).readableBytesView)
        span.attributes["http.response.status_code"] = Int(response.status.code)
        return (UInt(response.status.code), body)
    }

    private func outcome(status: UInt, body: Data, span: any Span) throws -> WorldResponseOutcome {
        switch status {
        case 202, 200:
            let result = try WorldJSON.makeDecoder().decode(
                CharacterDeliveryResult.self, from: body)
            span.attributes["conversation.delivery.route"] = result.outcome.route.rawValue
            span.attributes["conversation.delivery.disposition"] = result.disposition.rawValue
            Counter(
                label: "creature_agent.world.responses",
                dimensions: [("disposition", result.disposition.rawValue)]
            ).increment()
            return result.disposition == .accepted
                ? .accepted(result.outcome)
                : .duplicate(result.outcome)
        case 400..<500:
            let error =
                (try? WorldJSON.makeDecoder().decode(WorldErrorBody.self, from: body))
                ?? WorldErrorBody(error: "rejected", message: "HTTP \(status)")
            span.attributes["conversation.delivery.disposition"] = "rejected"
            span.attributes["error.type"] = error.error
            Counter(
                label: "creature_agent.world.responses",
                dimensions: [("disposition", "rejected")]
            ).increment()
            return .rejected(code: error.error, message: error.message)
        default:
            throw WorldResponderError.unavailable(status: status)
        }
    }

    /// A 4xx becomes a rejection the caller can reason about; anything else is the world away.
    private static func failure(status: UInt, body: Data) -> WorldResponderError {
        guard (400..<500).contains(status) else {
            return .unavailable(status: status)
        }
        let error =
            (try? WorldJSON.makeDecoder().decode(WorldErrorBody.self, from: body))
            ?? WorldErrorBody(error: "rejected", message: "HTTP \(status)")
        return .rejected(code: error.error, message: error.message)
    }
}

extension WorldResponder: WorldSessionClient {
    func login(_ characterID: EntityID, _ loginRequest: CharacterLoginRequest) async throws
        -> CharacterLoginResult
    {
        try await withSpan("creature.world.login", ofKind: .client) { span in
            let (status, body) = try await post(
                loginRequest, path: ["characters", characterID.rawValue, "login"], span: span)
            // 409 carries the session that holds the character; it is an answer, not an error.
            guard status == 200 || status == 409 else {
                throw Self.failure(status: status, body: body)
            }
            return try WorldJSON.makeDecoder().decode(CharacterLoginResult.self, from: body)
        }
    }

    func heartbeat(_ characterID: EntityID, _ reference: CharacterSessionReference) async throws
        -> CharacterSession
    {
        let (status, body) = try await withSpan("creature.world.heartbeat", ofKind: .client) {
            span in
            try await post(
                reference, path: ["characters", characterID.rawValue, "heartbeat"], span: span)
        }
        guard status == 200 else { throw Self.failure(status: status, body: body) }
        return try WorldJSON.makeDecoder().decode(CharacterSession.self, from: body)
    }

    func logout(_ characterID: EntityID, _ reference: CharacterSessionReference) async throws
        -> CharacterSession
    {
        let (status, body) = try await withSpan("creature.world.logout", ofKind: .client) {
            span in
            try await post(
                reference, path: ["characters", characterID.rawValue, "logout"], span: span)
        }
        guard status == 200 else { throw Self.failure(status: status, body: body) }
        return try WorldJSON.makeDecoder().decode(CharacterSession.self, from: body)
    }
}

private struct WorldErrorBody: Decodable {
    let error: String
    let message: String
}

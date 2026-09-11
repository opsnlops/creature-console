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
}

/// Something that can carry Beaky's turn to the world.
protocol WorldTurnResponding: Sendable {
    func submit(_ intent: CharacterUtteranceIntent) async throws -> WorldResponseOutcome
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

    func submit(_ intent: CharacterUtteranceIntent) async throws -> WorldResponseOutcome {
        try await withSpan("creature.world.respond", ofKind: .client) { span in
            span.attributes["conversation.id"] = intent.conversationID.rawValue
            span.attributes["conversation.response.id"] = intent.responseID.rawValue

            let url =
                worldURL
                .appending(path: "conversations")
                .appending(path: intent.conversationID.rawValue)
                .appending(path: "responses")
            var request = HTTPClientRequest(url: url.absoluteString)
            request.method = .POST
            request.headers.add(name: "content-type", value: "application/json")
            request.body = .bytes(try WorldJSON.makeEncoder().encode(intent))
            let response = try await client.execute(request, timeout: .seconds(15), logger: logger)
            // NIOCore's readableBytesView works on Linux, where ByteBuffer has no Data bridge.
            let body = Data(try await response.body.collect(upTo: 1_048_576).readableBytesView)
            span.attributes["http.response.status_code"] = Int(response.status.code)

            switch response.status.code {
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
                    ?? WorldErrorBody(error: "rejected", message: "HTTP \(response.status.code)")
                span.attributes["conversation.delivery.disposition"] = "rejected"
                span.attributes["error.type"] = error.error
                Counter(
                    label: "creature_agent.world.responses",
                    dimensions: [("disposition", "rejected")]
                ).increment()
                return .rejected(code: error.error, message: error.message)
            default:
                throw WorldResponderError.unavailable(status: UInt(response.status.code))
            }
        }
    }
}

private struct WorldErrorBody: Decodable {
    let error: String
    let message: String
}

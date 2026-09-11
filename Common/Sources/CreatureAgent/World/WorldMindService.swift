import AsyncHTTPClient
import Foundation
import Logging
import ServiceLifecycle
import WorldCore

/// The world-resident mind as a long-running service: follow the world, consider each percept
/// in order, carry a reply to the world when there is one, and record silence when there is
/// not. The cursor moves only after each decision is durable.
struct WorldMindService: Service {
    private let subscriber: WorldPerceptSubscriber
    private let mind: CharacterMind
    private let responder: WorldResponder
    private let client: HTTPClient
    private let logger: Logger
    private let clock: any WorldClock

    init(
        subscriber: WorldPerceptSubscriber,
        mind: CharacterMind,
        responder: WorldResponder,
        client: HTTPClient,
        logger: Logger,
        clock: any WorldClock = SystemWorldClock()
    ) {
        self.subscriber = subscriber
        self.mind = mind
        self.responder = responder
        self.client = client
        self.logger = logger
        self.clock = clock
    }

    func run() async throws {
        do {
            try await withGracefulShutdownHandler {
                try await subscriber.run { consideration in
                    try await handle(consideration)
                }
            } onGracefulShutdown: {
                logger.info("Beaky's mind is going to sleep")
            }
        } catch is CancellationError {
            // Graceful shutdown cancels the stream; nothing undecided is lost.
        }
        try await client.shutdown()
    }

    /// Decides, then makes the decision durable in the world before returning so the cursor can
    /// move past this percept. Throws only when the world could not be reached, which retries
    /// the same consideration from the cursor.
    func handle(_ consideration: WorldConsideration) async throws {
        let decision = await mind.consider(consideration, now: await clock.now)
        guard case .reply(let intent) = decision else { return }

        switch try await responder.submit(intent) {
        case .accepted(let outcome):
            logger.info(
                "Beaky spoke",
                metadata: [
                    "conversation.response.id": "\(intent.responseID.rawValue)",
                    "conversation.delivery.route": "\(outcome.route.rawValue)",
                    "conversation.delivery.state": "\(outcome.state.rawValue)",
                ]
            )
        case .duplicate(let outcome):
            logger.info(
                "The world already carried this turn",
                metadata: [
                    "conversation.response.id": "\(intent.responseID.rawValue)",
                    "conversation.delivery.route": "\(outcome.route.rawValue)",
                ]
            )
        case .rejected(let code, let message):
            // Most likely a replay after a crash where the model phrased its answer differently:
            // the world kept the first version, which is the right outcome.
            logger.warning(
                "The world declined this turn; treating it as already decided",
                metadata: [
                    "conversation.response.id": "\(intent.responseID.rawValue)",
                    "error.type": "\(code)",
                    "error.message": "\(message)",
                ]
            )
        }
    }
}

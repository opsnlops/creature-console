import AsyncHTTPClient
import Foundation
import Logging
import ServiceLifecycle
import Tracing
import WorldCore

/// The world-resident mind as a long-running service: follow the world, consider each percept
/// in order, carry a reply to the world when there is one, and record silence when there is
/// not. The cursor moves only after each decision is durable.
struct WorldMindService: Service {
    private let subscriber: WorldPerceptSubscriber
    private let mind: CharacterMind
    private let responder: any WorldTurnResponding
    private let session: WorldCharacterSession?
    private let client: HTTPClient
    private let logger: Logger
    private let clock: any WorldClock
    private let spectateDelay: Duration

    /// Without a `session` the mind follows the world unconditionally (no login desk — the
    /// pre-0.5 world). With one it must hold its character before it follows anything.
    init(
        subscriber: WorldPerceptSubscriber,
        mind: CharacterMind,
        responder: any WorldTurnResponding,
        session: WorldCharacterSession? = nil,
        client: HTTPClient,
        logger: Logger,
        clock: any WorldClock = SystemWorldClock(),
        spectateDelay: Duration = .seconds(15)
    ) {
        self.subscriber = subscriber
        self.mind = mind
        self.responder = responder
        self.session = session
        self.client = client
        self.logger = logger
        self.clock = clock
        self.spectateDelay = spectateDelay
    }

    func run() async throws {
        // Graceful shutdown must cancel the stream subscription, not merely note it: the
        // subscriber otherwise keeps following the world and the service never returns.
        // Nothing undecided is lost — the cursor only moves after a decision is durable.
        do {
            try await cancelWhenGracefulShutdown {
                if let session {
                    try await runAsCharacter(session)
                } else {
                    try await follow()
                }
            }
        } catch is CancellationError {
            logger.info("Beaky's mind is going to sleep")
        }
        // Log out even when this task was cancelled outright (SIGINT, tests): the request runs
        // in its own task so the world learns the character is free instead of waiting for the
        // session to lapse.
        if let session {
            await Task { await session.logout() }.value
        }
        try await client.shutdown()
    }

    /// Log in, follow the world while the heartbeat holds, spectate when another mind has the
    /// character, and try again whenever the session is lost.
    private func runAsCharacter(_ session: WorldCharacterSession) async throws {
        while !Task.isCancelled {
            do {
                try await session.login()
            } catch WorldCharacterSessionError.loggedInElsewhere {
                try await Task.sleep(for: spectateDelay)
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning(
                    "Could not reach the world's login desk; trying again",
                    metadata: ["error": "\(error)"])
                try await Task.sleep(for: spectateDelay)
                continue
            }
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await session.keepAlive() }
                    group.addTask { try await follow() }
                    // Whichever ends first — a lost session or a failed follow — ends both.
                    try await group.next()
                    group.cancelAll()
                }
            } catch WorldCharacterSessionError.sessionLost {
                logger.warning(
                    "Lost the character; stopping until the world lets this mind back in")
            } catch is CancellationError {
                throw CancellationError()
            }
        }
    }

    private func follow() async throws {
        try await subscriber.run(
            handlers: WorldPerceptSubscriber.Handlers(
                utterance: { consideration in try await handle(consideration) },
                sceneOffer: { offer in try await handle(offer) }
            ))
    }

    /// The world offered this character the floor. Decide, then answer the world — a turn or a
    /// pass — before the cursor moves on. Throws only when the world could not be reached.
    func handle(_ offer: WorldSceneConsideration) async throws {
        try await withSpan(
            "agent.scene_turn",
            context: CharacterMind.traceContext(for: offer.envelope)
        ) { span in
            span.attributes["scene.id"] = offer.offer.sceneID.rawValue
            span.attributes["world.sequence"] = offer.worldSequence
            var submission: SceneTurnSubmission
            switch await mind.consider(offer, now: await clock.now) {
            case .turn(let turn):
                submission = turn
            case .pass(let pass, let reason):
                submission = pass
                span.attributes["agent.suppression_reason"] = reason.rawValue
            }
            submission.sessionID = await session?.sessionID
            let result = try await responder.submit(submission, to: offer.offer.sceneID)
            logger.info(
                submission.text == nil ? "Passed the floor" : "Took a turn in the scene",
                metadata: [
                    "scene.id": "\(offer.offer.sceneID.rawValue)",
                    "scene.turn.disposition": "\(result.disposition.rawValue)",
                    "scene.state": "\(result.scene.state.rawValue)",
                ]
            )
        }
    }

    /// Decides, then makes the decision durable in the world before returning so the cursor can
    /// move past this percept. Throws only when the world could not be reached, which retries
    /// the same consideration from the cursor.
    func handle(_ consideration: WorldConsideration) async throws {
        // One turn, one span: thinking and delivering both continue the trace April's words
        // arrived with, so Honeycomb shows ingress -> mind -> model -> reply as a single line.
        try await withSpan(
            "agent.turn",
            context: CharacterMind.traceContext(for: consideration.percept)
        ) { span in
            span.attributes["agent.consideration_id"] =
                consideration.percept.considerationID.rawValue
            span.attributes["world.sequence"] = consideration.worldSequence
            try await decideAndDeliver(consideration)
        }
    }

    private func decideAndDeliver(_ consideration: WorldConsideration) async throws {
        let decision = try await mind.consider(consideration, now: await clock.now)
        let intent: CharacterUtteranceIntent
        let outcome: WorldResponseOutcome
        switch decision {
        case .reply(let replyIntent):
            intent = replyIntent
            outcome = try await responder.submit(replyIntent)
        case .performed(let performance):
            intent = performance.intent
            outcome = try await responder.record(performance)
        case .alreadyDelivered(let responseID):
            logger.info(
                "The world had already carried this turn",
                metadata: ["conversation.response.id": "\(responseID.rawValue)"]
            )
            return
        case .silence:
            return
        }

        switch outcome {
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

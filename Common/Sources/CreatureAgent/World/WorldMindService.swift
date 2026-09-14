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
    /// The nightly memory, when this mind has a memory model; nil for the chorus.
    private let memory: MemoryJob?
    /// One night's work at a time.
    private let remembering = Remembering()

    private actor Remembering {
        private var task: Task<Void, Never>?
        /// Starts `work` unless a night is still being remembered; true when started.
        func start(_ work: @escaping @Sendable () async -> Void) -> Bool {
            if let task, !task.isCancelled { return false }
            let started = Task { await work() }
            task = started
            return true
        }
    }

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
        spectateDelay: Duration = .seconds(15),
        memory: MemoryJob? = nil
    ) {
        self.subscriber = subscriber
        self.mind = mind
        self.responder = responder
        self.session = session
        self.client = client
        self.logger = logger
        self.clock = clock
        self.spectateDelay = spectateDelay
        self.memory = memory
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
                sceneOffer: { offer in try await handle(offer) },
                consolidate: { event in await self.remember(event) }
            ))
    }

    /// "Remember the day": the job runs on its own so the stream keeps flowing; one at a time.
    func remember(_ event: WorldEventEnvelope) async {
        guard let memory else { return }
        guard case .string(let day)? = event.payload["day"] else { return }
        let clock = self.clock
        let logger = self.logger
        let started = await remembering.start {
            do {
                try await memory.remember(day: day, run: event.eventID, now: await clock.now)
            } catch {
                logger.error(
                    "Could not remember the day",
                    metadata: ["memory.day": "\(day)", "error": "\(error)"])
            }
        }
        if !started {
            logger.warning(
                "Still remembering the last day; skipping", metadata: ["memory.day": "\(day)"])
        }
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
            let sessionID = await session?.sessionID
            let sceneID = offer.offer.sceneID
            let characterID = offer.offer.characterID
            let responseID = offer.offer.responseID
            let responder = self.responder
            // Each sentence goes to the world as it is composed; the world speaks it and keeps
            // the floor open for the next.
            let streamed = Streamed()
            let envelope = offer.envelope
            let decision = try await mind.consider(
                offer, now: await clock.now,
                speak: { index, text in
                    let piece = try SceneTurnSubmission(
                        characterID: characterID, responseID: responseID, sessionID: sessionID,
                        text: text, piece: index)
                    let result = try await responder.submit(piece, to: sceneID)
                    await streamed.note(result.disposition)
                },
                learn: { learned in
                    await self.cast(learned, causedBy: envelope, key: responseID.rawValue)
                })
            switch decision {
            case .turn(let turn):
                submission = turn
            case .pass(let pass, let reason):
                submission = pass
                span.attributes["agent.suppression_reason"] = reason.rawValue
            }
            submission.sessionID = sessionID
            let pieces = await streamed.count
            span.attributes["scene.turn.pieces"] = pieces
            let result = try await responder.submit(submission, to: offer.offer.sceneID)
            logger.info(
                submission.text == nil && pieces == 0
                    ? "Passed the floor" : "Took a turn in the scene",
                metadata: [
                    "scene.id": "\(offer.offer.sceneID.rawValue)",
                    "scene.turn.disposition": "\(result.disposition.rawValue)",
                    "scene.turn.pieces": "\(pieces)",
                    "scene.state": "\(result.scene.state.rawValue)",
                ]
            )
        }
    }

    /// How many pieces of a streamed line the world took.
    private actor Streamed {
        private(set) var count = 0
        func note(_ disposition: SceneTurnDisposition) {
            if disposition == .accepted { count += 1 }
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

    /// What April told the mind becomes facts the world keeps: cast with her as the source,
    /// her words as provenance, and a source event id so a retried consideration casts once.
    /// A cast that fails is logged, never fatal - the reply already went out.
    private func cast(_ learned: [LearnedFact], causedBy envelope: WorldEventEnvelope, key: String)
        async
    {
        let now = await clock.now
        for (index, fact) in learned.enumerated() {
            do {
                var payload: [String: WorldJSONValue] = [
                    "subject_id": .string(fact.subjectID.rawValue),
                    "predicate": .string(fact.predicate),
                    "value": .string(fact.value),
                ]
                if let seconds = fact.expiry.seconds(from: now, in: mind.configuration.timeZone) {
                    payload["valid_for_seconds"] = .number(seconds)
                }
                let event = try WorldEventEnvelope(
                    type: WorldEventType(validating: "facts.given"),
                    occurredAt: now,
                    source: EventSource(
                        id: try SourceID(validating: "mind:\(mind.configuration.characterName)"),
                        kind: "mind", sourceEventID: "\(key):learned:\(index)"),
                    subjectIDs: [fact.subjectID],
                    epistemic: EpistemicState(type: .reported, confidence: 1),
                    payload: payload,
                    causedBy: [.event(envelope.eventID)],
                    trace: envelope.trace)
                try await responder.cast(event)
                logger.info(
                    "Learned something from April",
                    metadata: [
                        "subject": "\(fact.subjectID.rawValue)", "predicate": "\(fact.predicate)",
                        "value": "\(fact.value)", "expires": "\(fact.expiry.rawValue)",
                    ])
            } catch {
                logger.error(
                    "Could not tell the world what April said",
                    metadata: ["error": "\(error)", "predicate": "\(fact.predicate)"])
            }
        }
    }

    private func decideAndDeliver(_ consideration: WorldConsideration) async throws {
        let envelope = consideration.envelope
        let key = consideration.percept.considerationID.rawValue
        let decision = try await mind.consider(consideration, now: await clock.now) { learned in
            await self.cast(learned, causedBy: envelope, key: key)
        }
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

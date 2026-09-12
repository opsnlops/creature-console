import Foundation
import Instrumentation
import Logging
import Metrics
import ServiceContextModule
import Tracing
import WorldCore

/// What Beaky decided to do about one thing the world offered her.
enum CharacterDecision: Equatable, Sendable {
    /// Words for the world to carry on the stage it chooses.
    case reply(CharacterUtteranceIntent)
    /// Words she already said herself, in the room, on the stage the world decided.
    case performed(CharacterPerformance)
    /// The world had already carried this turn (a replay after a crash); nothing more to do.
    case alreadyDelivered(ResponseID)
    case silence(reason: SilenceReason)

    enum SilenceReason: String, Equatable, Sendable {
        /// The utterance is older than the mind is willing to answer.
        case stale
        /// The utterance was not spoken by the person this mind answers.
        case notAddressed = "not_addressed"
        /// The model was asked and chose to say nothing.
        case choseSilence = "chose_silence"
        /// The model returned nothing usable after sanitizing.
        case emptyResponse = "empty_response"
        /// The model did not answer in time or failed.
        case modelUnavailable = "model_unavailable"
        /// The world opened a scene for this utterance; the floor comes separately.
        case inScene = "in_scene"
    }
}

/// What a character does when the world offers it the floor in a scene.
enum SceneDecision: Equatable, Sendable {
    case turn(SceneTurnSubmission)
    case pass(SceneTurnSubmission, reason: CharacterDecision.SilenceReason)
}

/// The character's reasoning over one percept: deterministic guardrails, a bounded prompt
/// built from the canonical conversation, a local model call, and deterministic validation.
///
/// The mind authors words. It never chooses a transport, and it never reads anything the world
/// did not put in the percept.
struct CharacterMind: Sendable {
    typealias Respond = @Sendable ([LocalLLMClient.Message]) async throws -> String
    /// The model's answer as sentences, in order, as they are produced.
    typealias RespondStreaming = @Sendable ([LocalLLMClient.Message]) -> AsyncStream<String>

    /// Where the world put Beaky for this turn, and what she has to perform it with.
    struct Stage: Sendable {
        let stager: any WorldStaging
        let room: any PhysicalSpeechStaging
        let respondStreaming: RespondStreaming
        /// The session this mind holds for its character, so the world can tell it from a
        /// second copy of the same character. `nil` when the world has no logins yet.
        let session: @Sendable () async -> CharacterSessionID?

        init(
            stager: any WorldStaging,
            room: any PhysicalSpeechStaging,
            respondStreaming: @escaping RespondStreaming,
            session: @escaping @Sendable () async -> CharacterSessionID? = { nil }
        ) {
            self.stager = stager
            self.room = room
            self.respondStreaming = respondStreaming
            self.session = session
        }
    }

    /// Bumped whenever the prompt contract changes so evaluations stay comparable.
    static let promptVersion = "world-conversation-v2"
    /// The one reserved reply: the model may decline to speak.
    static let silenceToken = "[silence]"

    struct Configuration: Sendable {
        let persona: CharacterPersona
        let characterID: EntityID
        let personID: EntityID
        let maximumReplyAge: TimeInterval
        let maximumContextTurns: Int
        let modelTimeout: Duration
        let modelName: String
        var timeZone: TimeZone = .current
        /// `backend/model` ("openai/gpt-6-astra"): the mind is told what it runs on, so April
        /// can ask her which bird is thinking on what.
        var modelLabel: String? = nil

        /// The character's plain name, as a model might label her lines: `character:beaky` → `beaky`.
        var characterName: String {
            let raw = characterID.rawValue
            guard let colon = raw.firstIndex(of: ":") else { return raw }
            return String(raw[raw.index(after: colon)...])
        }
    }

    let configuration: Configuration
    private let respond: Respond
    private let stage: Stage?
    private let logger: Logger
    private let considerationCounter = Counter(label: "creature_agent.considerations")
    private let replyCounter = Counter(
        label: "creature_agent.considerations.outcome",
        dimensions: [("outcome", "reply")]
    )

    /// Without a `stage`, every reply goes to the world for routing (the Communicator path).
    /// With one, the mind asks the world where April can hear her before generating and, if the
    /// answer is the room, speaks sentence by sentence while the model is still thinking.
    init(
        configuration: Configuration,
        respond: @escaping Respond,
        stage: Stage? = nil,
        logger: Logger
    ) {
        self.configuration = configuration
        self.respond = respond
        self.stage = stage
        self.logger = logger
    }

    /// Throws only when the world could not be asked for the stage, so the caller retries the
    /// same consideration from its cursor; every other trouble becomes a recorded decision.
    func consider(_ consideration: WorldConsideration, now: Date) async throws -> CharacterDecision
    {
        let percept = consideration.percept
        // Inside an `agent.turn` span this nests naturally; on its own it continues the trace
        // the utterance arrived with.
        let context = ServiceContext.current ?? Self.traceContext(for: percept)
        return try await withSpan("agent.consider", context: context) { span in
            span.attributes["agent.character_id"] = configuration.characterID.rawValue
            span.attributes["agent.consideration_id"] = percept.considerationID.rawValue
            span.attributes["conversation.id"] = percept.utterance.conversationID.rawValue
            span.attributes["conversation.utterance.id"] = percept.utterance.utteranceID.rawValue
            span.attributes["world.sequence"] = consideration.worldSequence
            span.attributes["agent.prompt_version"] = Self.promptVersion
            span.attributes["agent.persona_version"] = configuration.persona.versionTag
            span.attributes["llm.model"] = configuration.modelName
            considerationCounter.increment()

            let decision = try await decide(consideration, now: now)
            switch decision {
            case .reply:
                span.attributes["agent.reaction"] = "reply"
                replyCounter.increment()
            case .performed(let performance):
                span.attributes["agent.reaction"] = "performed"
                span.attributes["conversation.delivery.state"] = performance.outcome.state.rawValue
                replyCounter.increment()
            case .alreadyDelivered:
                span.attributes["agent.reaction"] = "already_delivered"
            case .silence(let reason):
                span.attributes["agent.reaction"] = "silence"
                span.attributes["agent.suppression_reason"] = reason.rawValue
                Counter(
                    label: "creature_agent.considerations.outcome",
                    dimensions: [("outcome", "silence"), ("reason", reason.rawValue)]
                ).increment()
            }
            logDecision(decision, for: consideration)
            return decision
        }
    }

    private func decide(_ consideration: WorldConsideration, now: Date) async throws
        -> CharacterDecision
    {
        let utterance = consideration.percept.utterance

        // Deterministic guardrails come before any model call.
        guard utterance.speakerID == configuration.personID else {
            return .silence(reason: .notAddressed)
        }
        guard now.timeIntervalSince(utterance.occurredAt) <= configuration.maximumReplyAge else {
            return .silence(reason: .stale)
        }
        // The world opened a scene for these words; it will offer the floor separately.
        guard consideration.percept.sceneID == nil else {
            return .silence(reason: .inScene)
        }

        let responseID = Self.responseID(for: consideration.percept.considerationID)

        // Ask the world where April can hear Beaky *before* thinking, so a turn for the room can
        // be spoken as it is produced instead of after it is complete.
        var decision: CharacterDeliveryDecision?
        if let stage {
            let staged = try await stage.stager.stage(
                CharacterStageRequest(
                    responseID: responseID,
                    characterID: configuration.characterID,
                    recipientID: utterance.speakerID,
                    sessionID: await stage.session()
                ),
                in: utterance.conversationID
            )
            guard staged.disposition == .decided else {
                return .alreadyDelivered(responseID)
            }
            decision = staged.decision
        }

        if let stage, let decision, decision.route == .physicalSpeech {
            return await performInTheRoom(
                consideration, decision: decision, responseID: responseID, stage: stage, now: now)
        }

        let transcript = makeTranscript(for: consideration.percept, route: .communicator, now: now)
        let raw: String
        do {
            raw = try await withSpan("llm.mistral.generate") { span in
                span.attributes["llm.model"] = configuration.modelName
                span.attributes["llm.transcript.turns"] = transcript.count
                return try await withTimeout(configuration.modelTimeout) {
                    try await respond(transcript)
                }
            }
        } catch {
            logger.error(
                "Beaky's model did not answer",
                metadata: [
                    "error": "\(error)",
                    "agent.consideration_id": "\(consideration.percept.considerationID.rawValue)",
                ]
            )
            return .silence(reason: .modelUnavailable)
        }

        guard let text = Self.validate(raw, spokenBy: configuration.characterName) else {
            let declined = Self.declinesToSpeak(raw)
            return .silence(reason: declined ? .choseSilence : .emptyResponse)
        }

        do {
            return .reply(
                try makeIntent(text: text, for: consideration, responseID: responseID, now: now))
        } catch {
            logger.error(
                "Beaky's answer did not form a valid turn",
                metadata: ["error": "\(error)"]
            )
            return .silence(reason: .emptyResponse)
        }
    }

    /// Speaks in the room while the model generates: each sentence is validated the moment it
    /// exists and handed to the physical stage, which opens Creature Server's session on the
    /// first one. The recorded turn is exactly the sentences that were offered to the room.
    private func performInTheRoom(
        _ consideration: WorldConsideration,
        decision: CharacterDeliveryDecision,
        responseID: ResponseID,
        stage: Stage,
        now: Date
    ) async -> CharacterDecision {
        let transcript = makeTranscript(
            for: consideration.percept, route: .physicalSpeech, now: now)
        let (sentenceStream, continuation) = AsyncStream<String>.makeStream()
        let name = configuration.characterName

        // The room and the model run together; the room finishes when the sentences do.
        async let performance: Result<String?, any Error> = {
            do {
                return .success(try await stage.room.perform(sentenceStream))
            } catch {
                return .failure(error)
            }
        }()

        let spoken = SpokenSentences(room: continuation)
        var modelFailed = false
        do {
            try await withSpan("llm.mistral.generate") { span in
                span.attributes["llm.model"] = configuration.modelName
                span.attributes["llm.transcript.turns"] = transcript.count
                span.attributes["llm.streaming"] = true
                // A timeout cancels the model loop; whatever was already offered to the room
                // stays spoken and recorded.
                try await withTimeout(configuration.modelTimeout) {
                    for await raw in stage.respondStreaming(transcript) {
                        guard await spoken.offer(raw, characterName: name) else { break }
                    }
                }
                span.attributes["speech.sentences"] = await spoken.sentences.count
            }
        } catch {
            modelFailed = true
            logger.error(
                "Beaky's model did not answer",
                metadata: [
                    "error": "\(error)",
                    "agent.consideration_id": "\(consideration.percept.considerationID.rawValue)",
                ]
            )
        }
        let sentences = await spoken.sentences
        let declined = await spoken.declined
        continuation.finish()
        let performed = await performance

        guard !sentences.isEmpty else {
            if modelFailed { return .silence(reason: .modelUnavailable) }
            return .silence(reason: declined ? .choseSilence : .emptyResponse)
        }
        let outcome: CharacterPerformanceReport
        do {
            switch performed {
            case .success(let reference):
                outcome = try CharacterPerformanceReport(
                    state: .performed, providerReference: reference)
            case .failure(let error as PhysicalSpeechStageError):
                logger.error("Beaky could not speak in the room", metadata: ["error": "\(error)"])
                outcome = try CharacterPerformanceReport(state: .failed, errorCode: error.code)
            case .failure(let error):
                logger.error("Beaky could not speak in the room", metadata: ["error": "\(error)"])
                outcome = try CharacterPerformanceReport(
                    state: .failed, errorCode: "physical_speech_unavailable")
            }
            let intent = try makeIntent(
                text: sentences.joined(separator: " "), for: consideration,
                responseID: responseID, now: now)
            return .performed(
                CharacterPerformance(
                    intent: intent, attemptID: decision.attemptID, outcome: outcome,
                    sessionID: await stage.session()))
        } catch {
            logger.error(
                "Beaky's answer did not form a valid turn",
                metadata: ["error": "\(error)"]
            )
            return .silence(reason: .emptyResponse)
        }
    }

    /// The sentences offered to the room so far, validated one at a time as the model produces
    /// them: the first decides silence and loses any speaker label, every one is speech-clean,
    /// and the turn stops at the world's length limit.
    private actor SpokenSentences {
        private(set) var sentences: [String] = []
        private(set) var declined = false
        private let room: AsyncStream<String>.Continuation

        init(room: AsyncStream<String>.Continuation) {
            self.room = room
        }

        /// Returns `false` when the turn is over: silence was chosen or the limit was reached.
        func offer(_ raw: String, characterName: String) -> Bool {
            let stripped = LocalLLMClient.stripThinkTags(raw)
            if sentences.isEmpty, CharacterMind.declinesToSpeak(stripped) {
                declined = true
                return false
            }
            let candidate =
                sentences.isEmpty
                ? CharacterMind.withoutSpeakerLabel(stripped, characterName: characterName)
                : stripped
            let clean = TextSanitizer.sanitize(candidate).text
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return true }
            guard CharacterMind.fits(sentences + [clean]) else { return false }
            sentences.append(clean)
            room.yield(clean)
            return true
        }
    }

    private func makeIntent(
        text: String,
        for consideration: WorldConsideration,
        responseID: ResponseID,
        now: Date
    ) throws -> CharacterUtteranceIntent {
        let utterance = consideration.percept.utterance
        return try CharacterUtteranceIntent(
            responseID: responseID,
            conversationID: utterance.conversationID,
            characterID: configuration.characterID,
            recipientID: utterance.speakerID,
            inResponseToUtteranceID: utterance.utteranceID,
            text: text,
            urgency: 0.3,
            createdAt: now,
            reasonReferences: [.event(consideration.envelope.eventID)],
            trace: currentTraceContext() ?? utterance.trace
        )
    }

    /// Whether the sentences so far fit the world's limit on one turn.
    static func fits(_ sentences: [String]) -> Bool {
        sentences.joined(separator: " ").unicodeScalars.count
            <= ConversationContractLimits.maximumTextUnicodeScalars
    }

    // MARK: - Scenes

    /// The world has offered this character the floor: something to add, or a pass. Composed as
    /// text only — the world performs the whole scene once it closes.
    func consider(_ offer: WorldSceneConsideration, now: Date) async -> SceneDecision {
        let context = ServiceContext.current ?? Self.traceContext(for: offer.envelope)
        return await withSpan("agent.scene.consider", context: context) { span in
            span.attributes["agent.character_id"] = configuration.characterID.rawValue
            span.attributes["scene.id"] = offer.offer.sceneID.rawValue
            span.attributes["world.sequence"] = offer.worldSequence
            span.attributes["agent.persona_version"] = configuration.persona.versionTag
            span.attributes["llm.model"] = configuration.modelName
            considerationCounter.increment()
            let decision = await decideTurn(offer.offer, now: now)
            switch decision {
            case .turn:
                span.attributes["agent.reaction"] = "turn"
                replyCounter.increment()
            case .pass(_, let reason):
                span.attributes["agent.reaction"] = "pass"
                span.attributes["agent.suppression_reason"] = reason.rawValue
                Counter(
                    label: "creature_agent.considerations.outcome",
                    dimensions: [("outcome", "pass"), ("reason", reason.rawValue)]
                ).increment()
            }
            return decision
        }
    }

    private func decideTurn(_ offer: SceneTurnOffer, now: Date) async -> SceneDecision {
        func pass(_ reason: CharacterDecision.SilenceReason) -> SceneDecision {
            .pass(
                try! SceneTurnSubmission(
                    characterID: configuration.characterID, responseID: offer.responseID,
                    sessionID: nil, text: nil),
                reason: reason)
        }
        guard now <= offer.deadline else { return pass(.stale) }
        let transcript = makeSceneTranscript(for: offer, now: now)
        let raw: String
        do {
            raw = try await withSpan("llm.mistral.generate") { span in
                span.attributes["llm.model"] = configuration.modelName
                span.attributes["llm.transcript.turns"] = transcript.count
                return try await withTimeout(configuration.modelTimeout) {
                    try await respond(transcript)
                }
            }
        } catch {
            logger.error(
                "The model did not answer the scene", metadata: ["error": "\(error)"])
            return pass(.modelUnavailable)
        }
        guard var text = Self.validate(raw, spokenBy: configuration.characterName) else {
            return pass(Self.declinesToSpeak(raw) ? .choseSilence : .emptyResponse)
        }
        if let speaker = offer.trigger.speakerID {
            text = Self.withoutOpeningVocative(text, name: Self.name(of: speaker))
        }
        do {
            return .turn(
                try SceneTurnSubmission(
                    characterID: configuration.characterID,
                    responseID: offer.responseID,
                    sessionID: nil,
                    text: text,
                    trace: currentTraceContext()
                ))
        } catch {
            return pass(.emptyResponse)
        }
    }

    /// The persona, the scene contract, then the scene so far as a script the model continues:
    /// the trigger as April's (or the world's) line, each turn as "Name: words".
    func makeSceneTranscript(for offer: SceneTurnOffer, now: Date = Date())
        -> [LocalLLMClient.Message]
    {
        let others = offer.participants.filter { $0 != configuration.characterID }
            .map(Self.name(of:))
        var present = offer.participants
        if let speaker = offer.trigger.speakerID {
            present.append(speaker)
        }
        var transcript = [
            LocalLLMClient.Message(
                role: .system,
                content: configuration.persona.rendered(
                    present: present, pronouns: FactPhrasing.pronouns(in: offer.worldFacts))
                    + "\n\n" + Self.sceneContract(others: others)
                    + knowledgeBlock(offer.worldFacts, now: now)
            )
        ]
        var script = ""
        switch offer.trigger.kind {
        case .personUtterance:
            let speaker = offer.trigger.speakerID.map(Self.name(of:)) ?? "April"
            script += "\(speaker): \(offer.trigger.text)\n"
        case .worldEvent:
            script += "(\(offer.trigger.text))\n"
        }
        for turn in offer.turns {
            guard let text = turn.text else { continue }
            script += "\(Self.name(of: turn.characterID)): \(text)\n"
        }
        script += "\(configuration.characterName.capitalized):"
        transcript.append(LocalLLMClient.Message(role: .user, content: script))
        return transcript
    }

    static func name(of entityID: EntityID) -> String {
        FactPhrasing.name(of: entityID)
    }

    /// "What you know": the local time in words, then the world's facts in plain words. The
    /// time is always there — a model cannot work out time zones, so it is told — and the
    /// facts follow when the world has any.
    func knowledgeBlock(_ facts: [Fact], now: Date) -> String {
        var lines = [FactPhrasing.timeSentence(now, in: configuration.timeZone)]
        if let model = configuration.modelLabel {
            lines.append(
                "Your mind runs on the \(model) model. Say so if April asks; otherwise it is not worth mentioning."
            )
        }
        lines += FactPhrasing.lines(for: facts, character: configuration.characterID, now: now)
        return "\n\nWhat you know right now, from the world itself (trust this over guesses):\n"
            + lines.map { "- " + $0 }.joined(separator: "\n")
    }

    static func sceneContract(others: [String]) -> String {
        let company =
            others.isEmpty
            ? "You are alone with April in the room."
            : "In the room with you and April: \(others.joined(separator: ", ")). They speak for themselves; never speak for them."
        return """
            \(company) A scene is unfolding and it is your turn. The exchange so far is written \
            below as a script; continue it with only your own next line, in your own voice, in one \
            or two short sentences, spoken aloud. Speak to whoever you are answering, a bird or \
            April, and do not begin your line with anyone's name unless you are singling them out. \
            Do not write anyone else's line and do not prefix your words with your name. If you \
            have nothing to add, reply with exactly \(silenceToken) and nothing else. Never use \
            emoji or symbols. Do not describe actions.
            """
    }

    /// The trace context the world attached to the utterance, as a span parent.
    static func traceContext(for percept: PersonUtterancePercept) -> ServiceContext {
        traceContext(from: percept.utterance.trace)
    }

    static func traceContext(for envelope: WorldEventEnvelope) -> ServiceContext {
        traceContext(from: envelope.trace)
    }

    private static func traceContext(from trace: W3CTraceContext?) -> ServiceContext {
        var context = ServiceContext.topLevel
        if let trace {
            InstrumentationSystem.instrument.extract(
                trace.carrier,
                into: &context,
                using: TraceContextExtractor()
            )
        }
        return context
    }

    // MARK: - Prompt

    /// The persona, the conversation contract, then the canonical conversation as it happened:
    /// April's turns as `user`, Beaky's own earlier turns as `assistant`, newest last.
    func makeTranscript(
        for percept: PersonUtterancePercept,
        route: CharacterDeliveryRoute = .communicator,
        now: Date = Date()
    ) -> [LocalLLMClient.Message] {
        // Who is here: the speaker, and every character the world says is in a region.
        let present =
            [percept.utterance.speakerID]
            + FactPhrasing.presentCharacters(in: percept.worldFacts)
        var transcript = [
            LocalLLMClient.Message(
                role: .system,
                content: configuration.persona.rendered(
                    present: present, pronouns: FactPhrasing.pronouns(in: percept.worldFacts))
                    + "\n\n" + Self.contract(for: route)
                    + knowledgeBlock(percept.worldFacts, now: now)
            )
        ]
        let prior = percept.priorConversationItems
            .sorted { ($0.createdAt, $0.itemID.rawValue) < ($1.createdAt, $1.itemID.rawValue) }
            .suffix(configuration.maximumContextTurns)
        var turns = prior.map {
            LocalLLMClient.Message(
                role: $0.authorKind == .character ? .assistant : .user,
                content: $0.text
            )
        }
        turns.append(LocalLLMClient.Message(role: .user, content: percept.utterance.text))
        transcript.append(
            contentsOf: Self.openingWithTheUser(Self.coalescingConsecutiveTurns(turns)))
        return transcript
    }

    /// Chat templates such as Mistral's also require the first turn after the system message to
    /// be the user's. When the bounded window happens to open on one of Beaky's own earlier turns,
    /// that turn is dropped; the conversation still alternates and still ends with April.
    static func openingWithTheUser(
        _ turns: [LocalLLMClient.Message]
    ) -> [LocalLLMClient.Message] {
        Array(turns.drop(while: { $0.role == .assistant }))
    }

    /// Several messages in a row from the same author become one turn. Chat templates such as
    /// Mistral's require strict user/assistant alternation and reject the request otherwise, and
    /// a run of April's messages reads as one thought anyway.
    static func coalescingConsecutiveTurns(
        _ turns: [LocalLLMClient.Message]
    ) -> [LocalLLMClient.Message] {
        var merged: [LocalLLMClient.Message] = []
        for turn in turns {
            if let last = merged.last, last.role == turn.role {
                merged[merged.count - 1] = LocalLLMClient.Message(
                    role: last.role,
                    content: last.content + "\n" + turn.content
                )
            } else {
                merged.append(turn)
            }
        }
        return merged
    }

    static let contract = contract(for: .communicator)

    /// The same contract on either stage; only the first sentence says where April is.
    static func contract(for route: CharacterDeliveryRoute) -> String {
        let setting =
            switch route {
            case .physicalSpeech:
                "April is in the room with you and hears you speak aloud with your own voice."
            case .communicator:
                "You are talking with April through the Beaky Communicator app on her phone or Mac."
            }
        return """
            \(setting) \
            The conversation so far is shown above; the newest message is hers. Answer her in your \
            own voice in one to three short sentences. If you truly have nothing to add, reply with \
            exactly \(silenceToken) and nothing else. Your words are spoken aloud by your voice, so \
            never use emoji or symbols. Do not describe actions and do not mention that you are a \
            program.
            """
    }

    // MARK: - Validation

    /// The reply the world may carry, or `nil` when the model produced nothing usable.
    static func validate(_ raw: String, spokenBy characterName: String) -> String? {
        let stripped = LocalLLMClient.stripThinkTags(raw)
        guard !declinesToSpeak(stripped) else { return nil }
        // Her words are written to be spoken: the ad-hoc pipeline drops emoji and symbols, and
        // Communicator shows the same text, so they are removed here once for every stage.
        let sanitized = TextSanitizer.sanitize(
            withoutStageDirections(withoutSpeakerLabel(stripped, characterName: characterName))
        ).text
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }
        return truncatedAtSentence(
            sanitized,
            maximumUnicodeScalars: ConversationContractLimits.maximumTextUnicodeScalars
        )
    }

    /// A small model sometimes answers as a script — `Beaky: "…"` — especially after being
    /// addressed by name. Only her words are hers; the label is dropped so the format never
    /// reaches the conversation and teaches her next turn to copy it (#154).
    static func withoutSpeakerLabel(_ text: String, characterName: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return trimmed }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        // At the start, "Beaky:" / "Beaky said:" is a label. Later in the line — "Mango, what
        // do you think? Mango: Better on Linux." — the model interviewed itself, and only what
        // follows its own label is its line.
        let leading = "^\\s*\(escaped)(?:\\s+said)?\\s*:\\s*"
        let midline = "^.*?(?:^|[\\s\"'(])\(escaped)\\s*:\\s+"
        guard
            let expression = try? NSRegularExpression(
                pattern: "(?:\(leading))|(?:\(midline))", options: .caseInsensitive)
        else { return trimmed }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let stripped = expression.stringByReplacingMatches(
            in: trimmed, range: range, withTemplate: "")
        guard !stripped.isEmpty, stripped != trimmed else { return trimmed }
        return stripped.prefix(1).uppercased() + stripped.dropFirst()
    }

    /// The model was asked for exactly `[silence]`; a small model writes `Silence`, `*silence*`
    /// or `(silence)` just as readily, and none of those may be spoken aloud (#162).
    /// A small model narrates: `*giggles*`, `(chuckles)`, `[flaps wings]`. Nothing between
    /// asterisks or brackets is speech, so it is removed before the words are spoken — the
    /// persona's `never` rules make it rare; this makes it impossible. A stray opening quote
    /// left behind ("*giggles* "I love you") is trimmed with the rest.
    static func withoutStageDirections(_ text: String) -> String {
        let pattern = #"\*[^*\n]{1,80}\*|\([^()\n]{1,80}\)|\[[^\[\]\n]{1,80}\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            .replacingOccurrences(
                of: #"\s{2,}"#, with: " ", options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// In a scene a small model opens every line with the human's name — "April, pizza or
    /// Linux?" sixty times in a row. Everyone in the room knows she is there, so a line that
    /// begins by hailing the person who started the scene loses the hail; a name later in the
    /// line, or anyone else's name, is left alone. Solo replies are not touched.
    static func withoutOpeningVocative(_ text: String, name: String) -> String {
        let pattern = "^\\s*\(NSRegularExpression.escapedPattern(for: name))\\s*[,!:;\u{2014}-]\\s*"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        guard !stripped.isEmpty, stripped != text else { return text }
        // "April, pizza sounds delightful" → "Pizza sounds delightful".
        return stripped.prefix(1).uppercased() + stripped.dropFirst()
    }

    static func declinesToSpeak(_ raw: String) -> Bool {
        let decoration = CharacterSet(charactersIn: "\"'.`*()[]_-!")
            .union(.whitespacesAndNewlines)
        var text = LocalLLMClient.stripThinkTags(raw).trimmingCharacters(in: decoration)
        // "Beaky: [Silence]" is still silence: drop a script-style speaker label first.
        if let colon = text.firstIndex(of: ":"),
            text[..<colon].allSatisfy({ $0.isLetter || $0.isWhitespace })
        {
            text = text[text.index(after: colon)...].trimmingCharacters(in: decoration)
        }
        return text.caseInsensitiveCompare("silence") == .orderedSame
    }

    static func truncatedAtSentence(_ text: String, maximumUnicodeScalars: Int) -> String {
        guard text.unicodeScalars.count > maximumUnicodeScalars else { return text }
        let scalars = Array(text.unicodeScalars.prefix(maximumUnicodeScalars))
        var candidate = String(String.UnicodeScalarView(scalars))
        if let boundary = candidate.lastIndex(where: { ".!?".contains($0) }) {
            candidate = String(candidate[...boundary])
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One consideration, one response identity: a replay after a crash reuses it, so the world
    /// can recognise a second attempt instead of hearing Beaky twice.
    static func responseID(for considerationID: ConsiderationID) -> ResponseID {
        let value = considerationID.rawValue.dropFirst(ConsiderationIDDomain.namespace.count + 1)
        return (try? ResponseID(validating: "\(ResponseIDDomain.namespace):\(value)"))
            ?? .generated()
    }

    // MARK: - Helpers

    private func logDecision(_ decision: CharacterDecision, for consideration: WorldConsideration) {
        var metadata: Logger.Metadata = [
            "agent.consideration_id": "\(consideration.percept.considerationID.rawValue)",
            "conversation.id": "\(consideration.percept.utterance.conversationID.rawValue)",
            "world.sequence": "\(consideration.worldSequence)",
        ]
        switch decision {
        case .reply(let intent):
            metadata["conversation.response.id"] = "\(intent.responseID.rawValue)"
            logger.info("Beaky has something to say", metadata: metadata)
        case .performed(let performance):
            metadata["conversation.response.id"] = "\(performance.intent.responseID.rawValue)"
            metadata["conversation.delivery.state"] = "\(performance.outcome.state.rawValue)"
            if let code = performance.outcome.errorCode {
                metadata["error.type"] = "\(code)"
            }
            if performance.outcome.state == .performed {
                logger.info("Beaky spoke in the room", metadata: metadata)
            } else {
                logger.warning("Beaky could not speak in the room", metadata: metadata)
            }
        case .alreadyDelivered(let responseID):
            metadata["conversation.response.id"] = "\(responseID.rawValue)"
            logger.info("Beaky had already answered this", metadata: metadata)
        case .silence(let reason):
            metadata["agent.suppression_reason"] = "\(reason.rawValue)"
            logger.info("Beaky stays quiet", metadata: metadata)
        }
    }

    private func currentTraceContext() -> W3CTraceContext? {
        guard let context = ServiceContext.current else { return nil }
        var carrier: [String: String] = [:]
        InstrumentationSystem.instrument.inject(
            context, into: &carrier, using: TraceContextInjector())
        guard let traceparent = carrier["traceparent"] else { return nil }
        return try? W3CTraceContext(traceparent: traceparent, tracestate: carrier["tracestate"])
    }
}

private func withTimeout<Value: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw CharacterMindError.modelTimedOut
        }
        guard let value = try await group.next() else { throw CharacterMindError.modelTimedOut }
        group.cancelAll()
        return value
    }
}

enum CharacterMindError: Error, Equatable {
    case modelTimedOut
}

extension W3CTraceContext {
    /// The context as HTTP-style header fields for instrument extraction.
    var carrier: [String: String] {
        var fields = ["traceparent": traceparent]
        if let tracestate { fields["tracestate"] = tracestate }
        return fields
    }
}

struct TraceContextExtractor: Instrumentation.Extractor {
    typealias Carrier = [String: String]

    func extract(key: String, from carrier: [String: String]) -> String? {
        carrier[key]
    }
}

struct TraceContextInjector: Instrumentation.Injector {
    typealias Carrier = [String: String]

    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}

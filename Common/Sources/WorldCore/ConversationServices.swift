import Foundation
import Tracing

public enum UtteranceIngressBoundary: String, Hashable, Sendable, Codable {
    case trustedLAN = "trusted_lan"
    case authenticatedGateway = "authenticated_gateway"
}

public struct UtteranceIngressContext: Hashable, Sendable, Codable {
    public var boundary: UtteranceIngressBoundary
    public var principalID: EntityID?

    public init(boundary: UtteranceIngressBoundary, principalID: EntityID? = nil) {
        self.boundary = boundary
        self.principalID = principalID
    }
}

public protocol UtteranceIngressAuthorizing: Sendable {
    func authorize(_ utterance: PersonUtterance, context: UtteranceIngressContext) async -> Bool
}

public struct BoundaryUtteranceIngressAuthorizer: UtteranceIngressAuthorizing {
    public init() {}

    public func authorize(
        _ utterance: PersonUtterance,
        context: UtteranceIngressContext
    ) async -> Bool {
        switch context.boundary {
        case .trustedLAN:
            true
        case .authenticatedGateway:
            context.principalID == utterance.speakerID
                && [.communicatorComposition, .communicatorReply].contains(utterance.source)
        }
    }
}

public enum UtteranceIngressProgress: String, Hashable, Sendable, Codable {
    case pending
    case perceptSubmitted = "percept_submitted"
}

public struct StoredUtteranceIngress: Hashable, Sendable, Codable {
    public var percept: PersonUtterancePercept
    public var conversationItem: ConversationItem
    public var progress: UtteranceIngressProgress

    public init(
        percept: PersonUtterancePercept,
        conversationItem: ConversationItem,
        progress: UtteranceIngressProgress = .pending
    ) {
        self.percept = percept
        self.conversationItem = conversationItem
        self.progress = progress
    }
}

public protocol UtteranceIngressRepository: Sendable {
    /// Returns the durable record for an already-seen utterance.
    func ingress(for utteranceID: UtteranceID) async throws -> StoredUtteranceIngress?
    func conversationItems(in conversationID: ConversationID) async throws -> [ConversationItem]
    /// Atomically returns the existing record or persists and returns `ingress`.
    func prepare(_ ingress: StoredUtteranceIngress) async throws -> StoredUtteranceIngress
    func markPerceptSubmitted(utteranceID: UtteranceID) async throws
}

public enum UtterancePerceptAcceptance: String, Hashable, Sendable, Codable {
    case accepted
    case duplicate
}

public protocol PersonUtterancePerceptSink: Sendable {
    func submit(_ percept: PersonUtterancePercept) async throws -> UtterancePerceptAcceptance
}

public enum UtteranceIngressDisposition: String, Hashable, Sendable, Codable {
    case accepted
    case duplicate
}

public struct UtteranceIngressResult: Hashable, Sendable, Codable {
    public var disposition: UtteranceIngressDisposition
    public var percept: PersonUtterancePercept
    public var conversationItem: ConversationItem

    public init(
        disposition: UtteranceIngressDisposition,
        percept: PersonUtterancePercept,
        conversationItem: ConversationItem
    ) {
        self.disposition = disposition
        self.percept = percept
        self.conversationItem = conversationItem
    }
}

public protocol PersonUtteranceIngress: Sendable {
    func ingest(
        _ utterance: PersonUtterance,
        context: UtteranceIngressContext
    ) async throws -> UtteranceIngressResult
}

public actor PersonUtteranceIngressService: PersonUtteranceIngress {
    public typealias ConsiderationIDGenerator = @Sendable () -> ConsiderationID
    public typealias ConversationItemIDGenerator = @Sendable () -> ConversationItemID

    private let repository: any UtteranceIngressRepository
    private let sink: any PersonUtterancePerceptSink
    private let authorizer: any UtteranceIngressAuthorizing
    private let makeConsiderationID: ConsiderationIDGenerator
    private let makeConversationItemID: ConversationItemIDGenerator

    public init(
        repository: any UtteranceIngressRepository,
        sink: any PersonUtterancePerceptSink,
        authorizer: any UtteranceIngressAuthorizing = BoundaryUtteranceIngressAuthorizer(),
        makeConsiderationID: @escaping ConsiderationIDGenerator = { .generated() },
        makeConversationItemID: @escaping ConversationItemIDGenerator = { .generated() }
    ) {
        self.repository = repository
        self.sink = sink
        self.authorizer = authorizer
        self.makeConsiderationID = makeConsiderationID
        self.makeConversationItemID = makeConversationItemID
    }

    public func ingest(
        _ utterance: PersonUtterance,
        context: UtteranceIngressContext
    ) async throws -> UtteranceIngressResult {
        try await withSpan("conversation.utterance.ingest") { span in
            Self.setIngressAttributes(on: span, utterance: utterance, context: context)
            guard await authorizer.authorize(utterance, context: context) else {
                span.attributes["conversation.ingress.authorized"] = false
                throw WorldContractError.unauthorizedUtteranceIngress
            }
            span.attributes["conversation.ingress.authorized"] = true

            if let stored = try await repository.ingress(for: utterance.utteranceID) {
                guard stored.percept.utterance.isSameUtterance(as: utterance) else {
                    throw WorldContractError.conflictingConversationIdentity
                }
                return try await submitIfNeeded(stored, span: span)
            }

            let priorItems = try await repository.conversationItems(
                in: utterance.conversationID
            )
            let characterID = utterance.addresseeIDs[0]
            let proposed = try StoredUtteranceIngress(
                percept: PersonUtterancePercept(
                    considerationID: makeConsiderationID(),
                    characterID: characterID,
                    utterance: utterance,
                    priorConversationItems: priorItems
                ),
                conversationItem: ConversationItem(
                    itemID: makeConversationItemID(),
                    conversationID: utterance.conversationID,
                    authorID: utterance.speakerID,
                    authorKind: .person,
                    text: utterance.text,
                    createdAt: utterance.occurredAt,
                    utteranceID: utterance.utteranceID,
                    trace: utterance.trace
                )
            )
            let stored = try await repository.prepare(proposed)
            guard stored.percept.utterance.isSameUtterance(as: utterance) else {
                throw WorldContractError.conflictingConversationIdentity
            }
            return try await submitIfNeeded(stored, span: span)
        }
    }

    private func submitIfNeeded(
        _ stored: StoredUtteranceIngress,
        span: any Span
    ) async throws -> UtteranceIngressResult {
        guard stored.progress == .pending else {
            span.attributes["conversation.utterance.disposition"] = "duplicate"
            return UtteranceIngressResult(
                disposition: .duplicate,
                percept: stored.percept,
                conversationItem: stored.conversationItem
            )
        }

        let acceptance = try await sink.submit(stored.percept)
        try await repository.markPerceptSubmitted(
            utteranceID: stored.percept.utterance.utteranceID
        )
        let disposition: UtteranceIngressDisposition =
            acceptance == .accepted ? .accepted : .duplicate
        span.attributes["conversation.utterance.disposition"] = disposition.rawValue
        return UtteranceIngressResult(
            disposition: disposition,
            percept: stored.percept,
            conversationItem: stored.conversationItem
        )
    }

    private static func setIngressAttributes(
        on span: any Span,
        utterance: PersonUtterance,
        context: UtteranceIngressContext
    ) {
        for (key, value) in ConversationTelemetry.ingressAttributes(
            utterance: utterance,
            context: context
        ) {
            span.attributes[key] = value
        }
    }
}

public struct PersonUtteranceAdapterInput: Hashable, Sendable {
    public var utteranceID: UtteranceID
    public var conversationID: ConversationID
    public var speakerID: EntityID
    public var addresseeIDs: [EntityID]
    public var inResponseToResponseID: ResponseID?
    public var text: String
    public var sourceID: SourceID
    public var occurredAt: Date
    public var receivedAt: Date?
    public var confidence: Double
    public var placeEvidence: UtterancePlaceEvidence?
    public var causedBy: [ProvenanceReference]
    public var trace: W3CTraceContext?

    public init(
        utteranceID: UtteranceID,
        conversationID: ConversationID,
        speakerID: EntityID,
        addresseeIDs: [EntityID],
        inResponseToResponseID: ResponseID? = nil,
        text: String,
        sourceID: SourceID,
        occurredAt: Date,
        receivedAt: Date? = nil,
        confidence: Double,
        placeEvidence: UtterancePlaceEvidence? = nil,
        causedBy: [ProvenanceReference] = [],
        trace: W3CTraceContext? = nil
    ) {
        self.utteranceID = utteranceID
        self.conversationID = conversationID
        self.speakerID = speakerID
        self.addresseeIDs = addresseeIDs
        self.inResponseToResponseID = inResponseToResponseID
        self.text = text
        self.sourceID = sourceID
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.confidence = confidence
        self.placeEvidence = placeEvidence
        self.causedBy = causedBy
        self.trace = trace
    }
}

public struct PersonUtteranceAdapter: Sendable {
    public let source: UtteranceSource
    public let modality: UtteranceModality

    public init(source: UtteranceSource, modality: UtteranceModality) {
        self.source = source
        self.modality = modality
    }

    public static let communicatorComposition = Self(
        source: .communicatorComposition,
        modality: .typed
    )
    public static let communicatorReply = Self(source: .communicatorReply, modality: .typed)
    public static let wizardMode = Self(source: .wizardMode, modality: .typed)
    public static let speechToText = Self(source: .speechToText, modality: .spoken)

    public func submit(
        _ input: PersonUtteranceAdapterInput,
        context: UtteranceIngressContext,
        to service: any PersonUtteranceIngress
    ) async throws -> UtteranceIngressResult {
        let utterance = try PersonUtterance(
            utteranceID: input.utteranceID,
            conversationID: input.conversationID,
            speakerID: input.speakerID,
            addresseeIDs: input.addresseeIDs,
            inResponseToResponseID: input.inResponseToResponseID,
            text: input.text,
            modality: modality,
            source: source,
            sourceID: input.sourceID,
            occurredAt: input.occurredAt,
            receivedAt: input.receivedAt,
            confidence: input.confidence,
            placeEvidence: input.placeEvidence,
            causedBy: input.causedBy,
            trace: input.trace
        )
        return try await service.ingest(utterance, context: context)
    }
}

public protocol PersonPresenceProviding: Sendable {
    func presence(for personID: EntityID) async throws -> PersonPresence
}

public struct DeliverySinkResult: Hashable, Sendable {
    public var state: CharacterDeliveryOutcomeState
    public var providerReference: String?
    public var errorCode: String?

    public init(
        state: CharacterDeliveryOutcomeState,
        providerReference: String? = nil,
        errorCode: String? = nil
    ) {
        self.state = state
        self.providerReference = providerReference
        self.errorCode = errorCode
    }
}

public protocol CharacterDeliverySink: Sendable {
    func deliver(
        _ intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision
    ) async throws -> DeliverySinkResult
}

public struct StoredCharacterDelivery: Hashable, Sendable, Codable {
    public var intent: CharacterUtteranceIntent
    public var decision: CharacterDeliveryDecision
    public var conversationItem: ConversationItem
    public var outcome: CharacterDeliveryOutcome?

    public init(
        intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision,
        conversationItem: ConversationItem,
        outcome: CharacterDeliveryOutcome? = nil
    ) {
        self.intent = intent
        self.decision = decision
        self.conversationItem = conversationItem
        self.outcome = outcome
    }
}

/// A stage decision the world made before the words existed, so a mind can perform while it
/// generates. Short-lived: it is only a promise about *where*, and presence may move on.
public struct StoredStageDecision: Hashable, Sendable, Codable {
    public var conversationID: ConversationID
    public var characterID: EntityID
    public var recipientID: EntityID
    public var decision: CharacterDeliveryDecision
    public var expiresAt: Date

    public init(
        conversationID: ConversationID,
        characterID: EntityID,
        recipientID: EntityID,
        decision: CharacterDeliveryDecision,
        expiresAt: Date
    ) {
        self.conversationID = conversationID
        self.characterID = characterID
        self.recipientID = recipientID
        self.decision = decision
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case characterID = "character_id"
        case recipientID = "recipient_id"
        case decision
        case expiresAt = "expires_at"
    }
}

public protocol CharacterDeliveryRepository: Sendable {
    /// Returns a durable decision before mutable presence is consulted again.
    func delivery(for responseID: ResponseID) async throws -> StoredCharacterDelivery?
    /// Atomically returns the existing record or persists and returns `delivery`.
    func prepare(_ delivery: StoredCharacterDelivery) async throws -> StoredCharacterDelivery
    func record(_ outcome: CharacterDeliveryOutcome) async throws
    /// The stage decision made for a turn that has not been carried yet, if any.
    func stageDecision(for responseID: ResponseID) async throws -> StoredStageDecision?
    /// Atomically returns the existing stage decision or persists and returns `stage`.
    func prepareStage(_ stage: StoredStageDecision) async throws -> StoredStageDecision
}

public enum CharacterDeliveryDisposition: String, Hashable, Sendable, Codable {
    case accepted
    case duplicate
}

/// What the world did with one character turn: whether this call handled it or found it already
/// handled, the recorded delivery outcome, and the canonical item now in the shared history.
public struct CharacterDeliveryResult: Hashable, Sendable, Codable {
    public var disposition: CharacterDeliveryDisposition
    public var outcome: CharacterDeliveryOutcome
    public var conversationItem: ConversationItem

    public init(
        disposition: CharacterDeliveryDisposition,
        outcome: CharacterDeliveryOutcome,
        conversationItem: ConversationItem
    ) {
        self.disposition = disposition
        self.outcome = outcome
        self.conversationItem = conversationItem
    }

    private enum CodingKeys: String, CodingKey {
        case disposition
        case outcome
        case conversationItem = "conversation_item"
    }
}

public actor CharacterDeliveryRouter {
    public typealias DeliveryAttemptIDGenerator = @Sendable () -> DeliveryAttemptID
    public typealias ConversationItemIDGenerator = @Sendable () -> ConversationItemID

    private let presenceProvider: any PersonPresenceProviding
    private let repository: any CharacterDeliveryRepository
    private let physicalSpeechSink: any CharacterDeliverySink
    private let communicatorSink: any CharacterDeliverySink
    private let clock: any WorldClock
    private let minimumPresenceConfidence: Double
    private let stageDecisionLifetime: TimeInterval
    private let makeAttemptID: DeliveryAttemptIDGenerator
    private let makeConversationItemID: ConversationItemIDGenerator

    public init(
        presenceProvider: any PersonPresenceProviding,
        repository: any CharacterDeliveryRepository,
        physicalSpeechSink: any CharacterDeliverySink,
        communicatorSink: any CharacterDeliverySink,
        clock: any WorldClock,
        minimumPresenceConfidence: Double = 0.8,
        stageDecisionLifetime: TimeInterval = 300,
        makeAttemptID: @escaping DeliveryAttemptIDGenerator = { .generated() },
        makeConversationItemID: @escaping ConversationItemIDGenerator = { .generated() }
    ) throws {
        guard minimumPresenceConfidence.isFinite,
            (0...1).contains(minimumPresenceConfidence)
        else {
            throw WorldContractError.invalidConfidence(minimumPresenceConfidence)
        }
        precondition(stageDecisionLifetime > 0)
        self.presenceProvider = presenceProvider
        self.repository = repository
        self.physicalSpeechSink = physicalSpeechSink
        self.communicatorSink = communicatorSink
        self.clock = clock
        self.minimumPresenceConfidence = minimumPresenceConfidence
        self.stageDecisionLifetime = stageDecisionLifetime
        self.makeAttemptID = makeAttemptID
        self.makeConversationItemID = makeConversationItemID
    }

    /// Decides the stage for a turn before its words exist, durably, so the mind can perform
    /// while it generates. Asking again for the same `response_id` returns the same decision;
    /// a turn that was already carried is reported as such so it is never performed twice.
    public func stage(
        _ request: CharacterStageRequest,
        in conversationID: ConversationID
    ) async throws -> CharacterStageResult {
        try await withSpan("conversation.response.stage") { span in
            span.attributes["conversation.id"] = conversationID.rawValue
            span.attributes["conversation.response.id"] = request.responseID.rawValue
            if let delivered = try await repository.delivery(for: request.responseID) {
                guard delivered.intent.conversationID == conversationID,
                    delivered.intent.characterID == request.characterID,
                    delivered.intent.recipientID == request.recipientID
                else { throw WorldContractError.conflictingConversationIdentity }
                let disposition: CharacterStageDisposition =
                    delivered.outcome == nil ? .decided : .alreadyDelivered
                span.attributes["conversation.stage.disposition"] = disposition.rawValue
                return CharacterStageResult(
                    disposition: disposition,
                    decision: delivered.decision,
                    delivery: CharacterDeliveryRecord(
                        intent: delivered.intent,
                        decision: delivered.decision,
                        outcome: delivered.outcome,
                        conversationItem: delivered.conversationItem
                    )
                )
            }
            let stored: StoredStageDecision
            if let existing = try await repository.stageDecision(for: request.responseID) {
                stored = existing
            } else {
                // Presence is read before the clock so evidence observed "now" is never a hair
                // in the future of the decision that uses it.
                let presence = try await presenceProvider.presence(for: request.recipientID)
                guard presence.personID == request.recipientID else {
                    throw WorldContractError.invalidPresenceEvidence
                }
                let now = await clock.now
                stored = try await repository.prepareStage(
                    StoredStageDecision(
                        conversationID: conversationID,
                        characterID: request.characterID,
                        recipientID: request.recipientID,
                        decision: try makeDecision(
                            responseID: request.responseID, presence: presence, now: now),
                        expiresAt: now.addingTimeInterval(stageDecisionLifetime)
                    )
                )
            }
            guard stored.conversationID == conversationID,
                stored.characterID == request.characterID,
                stored.recipientID == request.recipientID
            else { throw WorldContractError.conflictingConversationIdentity }
            span.attributes["conversation.stage.disposition"] =
                CharacterStageDisposition.decided.rawValue
            span.attributes["conversation.delivery.route"] = stored.decision.route.rawValue
            span.attributes["conversation.delivery.reason"] = stored.decision.reason.rawValue
            return CharacterStageResult(disposition: .decided, decision: stored.decision)
        }
    }

    /// Records a turn the mind performed itself on a stage the world decided: the canonical item,
    /// the decision it was performed on, and the outcome, in one step. Idempotent by
    /// `response_id`; a performance the world never staged is refused.
    public func recordPerformance(
        _ performance: CharacterPerformance,
        in conversationID: ConversationID
    ) async throws -> CharacterDeliveryResult {
        try await withSpan("conversation.response.perform") { span in
            let intent = performance.intent
            guard intent.conversationID == conversationID else {
                throw WorldContractError.conflictingConversationIdentity
            }
            let stored: StoredCharacterDelivery
            if let existing = try await repository.delivery(for: intent.responseID) {
                guard existing.intent.isSameIntent(as: intent),
                    existing.decision.attemptID == performance.attemptID
                else { throw WorldContractError.conflictingConversationIdentity }
                stored = existing
            } else {
                guard let staged = try await repository.stageDecision(for: intent.responseID),
                    staged.decision.attemptID == performance.attemptID,
                    staged.conversationID == conversationID,
                    staged.characterID == intent.characterID,
                    staged.recipientID == intent.recipientID
                else { throw WorldContractError.unstagedPerformance }
                stored = try await repository.prepare(
                    StoredCharacterDelivery(
                        intent: intent,
                        decision: staged.decision,
                        conversationItem: try makeConversationItem(for: intent)
                    )
                )
                guard stored.intent.isSameIntent(as: intent) else {
                    throw WorldContractError.conflictingConversationIdentity
                }
            }
            for (key, value) in ConversationTelemetry.deliveryAttributes(
                intent: stored.intent,
                decision: stored.decision
            ) {
                span.attributes[key] = value
            }
            if let outcome = stored.outcome {
                span.attributes["conversation.delivery.outcome"] = "duplicate"
                return CharacterDeliveryResult(
                    disposition: .duplicate,
                    outcome: outcome,
                    conversationItem: stored.conversationItem
                )
            }
            let outcome = CharacterDeliveryOutcome(
                attemptID: stored.decision.attemptID,
                responseID: stored.intent.responseID,
                route: stored.decision.route,
                state: performance.outcome.state,
                occurredAt: await clock.now,
                providerReference: performance.outcome.providerReference,
                errorCode: performance.outcome.errorCode
            )
            try await repository.record(outcome)
            span.attributes["conversation.delivery.outcome"] = outcome.state.rawValue
            return CharacterDeliveryResult(
                disposition: .accepted,
                outcome: outcome,
                conversationItem: stored.conversationItem
            )
        }
    }

    public func route(_ intent: CharacterUtteranceIntent) async throws -> CharacterDeliveryResult {
        try await withSpan("conversation.response.route") { span in
            let stored: StoredCharacterDelivery
            if let existing = try await repository.delivery(for: intent.responseID) {
                guard existing.intent.isSameIntent(as: intent) else {
                    throw WorldContractError.conflictingConversationIdentity
                }
                stored = existing
            } else {
                // A mind that asked for the stage first is routed exactly as it was told.
                let proposedDecision: CharacterDeliveryDecision
                if let staged = try await repository.stageDecision(for: intent.responseID),
                    staged.conversationID == intent.conversationID,
                    staged.characterID == intent.characterID,
                    staged.recipientID == intent.recipientID
                {
                    proposedDecision = staged.decision
                } else {
                    let presence = try await presenceProvider.presence(for: intent.recipientID)
                    guard presence.personID == intent.recipientID else {
                        throw WorldContractError.invalidPresenceEvidence
                    }
                    let now = await clock.now
                    proposedDecision = try makeDecision(
                        responseID: intent.responseID, presence: presence, now: now)
                }
                stored = try await repository.prepare(
                    StoredCharacterDelivery(
                        intent: intent,
                        decision: proposedDecision,
                        conversationItem: try makeConversationItem(for: intent)
                    )
                )
                guard stored.intent.isSameIntent(as: intent) else {
                    throw WorldContractError.conflictingConversationIdentity
                }
            }

            for (key, value) in ConversationTelemetry.deliveryAttributes(
                intent: stored.intent,
                decision: stored.decision
            ) {
                span.attributes[key] = value
            }

            if let outcome = stored.outcome {
                span.attributes["conversation.delivery.outcome"] = "duplicate"
                return CharacterDeliveryResult(
                    disposition: .duplicate,
                    outcome: outcome,
                    conversationItem: stored.conversationItem
                )
            }

            let sink =
                stored.decision.route == .physicalSpeech ? physicalSpeechSink : communicatorSink
            let result = try await sink.deliver(stored.intent, decision: stored.decision)
            let outcome = CharacterDeliveryOutcome(
                attemptID: stored.decision.attemptID,
                responseID: stored.intent.responseID,
                route: stored.decision.route,
                state: result.state,
                occurredAt: await clock.now,
                providerReference: result.providerReference,
                errorCode: result.errorCode
            )
            try await repository.record(outcome)
            span.attributes["conversation.delivery.outcome"] = outcome.state.rawValue
            return CharacterDeliveryResult(
                disposition: .accepted,
                outcome: outcome,
                conversationItem: stored.conversationItem
            )
        }
    }

    private func makeConversationItem(for intent: CharacterUtteranceIntent) throws
        -> ConversationItem
    {
        try ConversationItem(
            itemID: makeConversationItemID(),
            conversationID: intent.conversationID,
            authorID: intent.characterID,
            authorKind: .character,
            text: intent.text,
            createdAt: intent.createdAt,
            responseID: intent.responseID,
            trace: intent.trace
        )
    }

    private func makeDecision(
        responseID: ResponseID,
        presence: PersonPresence,
        now: Date
    ) throws -> CharacterDeliveryDecision {
        let isFresh = presence.observedAt <= now && presence.validUntil >= now
        let isConfident = presence.confidence >= minimumPresenceConfidence
        let route: CharacterDeliveryRoute
        let privacyMode: CommunicatorPrivacyMode
        let reason: CharacterDeliveryReason

        if isFresh, isConfident, presence.state == .home, presence.physicallyAudible {
            route = .physicalSpeech
            privacyMode = .notApplicable
            reason = .homeAndAudible
        } else if isFresh, isConfident, presence.state == .away {
            route = .communicator
            privacyMode = .preview
            reason = .confidentlyAway
        } else {
            route = .communicator
            privacyMode = .private
            reason = .presenceUncertain
        }

        return try CharacterDeliveryDecision(
            attemptID: makeAttemptID(),
            responseID: responseID,
            route: route,
            privacyMode: privacyMode,
            reason: reason,
            decidedAt: now,
            presence: presence
        )
    }
}

enum ConversationTelemetry {
    static func ingressAttributes(
        utterance: PersonUtterance,
        context: UtteranceIngressContext
    ) -> [String: String] {
        [
            "conversation.utterance.id": utterance.utteranceID.rawValue,
            "conversation.id": utterance.conversationID.rawValue,
            "conversation.utterance.source": utterance.source.rawValue,
            "conversation.utterance.modality": utterance.modality.rawValue,
            "conversation.ingress.boundary": context.boundary.rawValue,
        ]
    }

    static func deliveryAttributes(
        intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision
    ) -> [String: String] {
        [
            "conversation.response.id": intent.responseID.rawValue,
            "conversation.id": intent.conversationID.rawValue,
            "conversation.delivery.attempt.id": decision.attemptID.rawValue,
            "conversation.delivery.route": decision.route.rawValue,
            "conversation.delivery.reason": decision.reason.rawValue,
            "conversation.delivery.privacy_mode": decision.privacyMode.rawValue,
        ]
    }
}

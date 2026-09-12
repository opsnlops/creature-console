import Foundation

public enum ConversationContractLimits {
    /// Bounds sensitive text consistently with JSON Schema's Unicode-code-point `maxLength`.
    public static let maximumTextUnicodeScalars = 4_096
    /// Bounds the prior conversation excerpt submitted for one consideration.
    public static let maximumContextItems = 100
}

func validateConversationText(_ text: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw WorldContractError.emptyUtterance
    }
    guard text.unicodeScalars.count <= ConversationContractLimits.maximumTextUnicodeScalars else {
        throw WorldContractError.conversationContentTooLarge(
            maximumUnicodeScalars: ConversationContractLimits.maximumTextUnicodeScalars
        )
    }
}

public enum UtteranceModality: String, Hashable, Sendable, Codable, CaseIterable {
    case typed
    case spoken
}

public enum UtteranceSource: String, Hashable, Sendable, Codable, CaseIterable {
    case communicatorComposition = "communicator_composition"
    case communicatorReply = "communicator_reply"
    case wizardMode = "wizard_mode"
    case speechToText = "speech_to_text"
}

public struct UtterancePlaceEvidence: Hashable, Sendable, Codable {
    public var placeID: EntityID
    public var confidence: Double
    public var observedAt: Date
    public var validUntil: Date
    public var provenance: [ProvenanceReference]

    public init(
        placeID: EntityID,
        confidence: Double,
        observedAt: Date,
        validUntil: Date,
        provenance: [ProvenanceReference] = []
    ) throws {
        guard confidence.isFinite, (0...1).contains(confidence), validUntil >= observedAt else {
            throw WorldContractError.invalidPresenceEvidence
        }
        self.placeID = placeID
        self.confidence = confidence
        self.observedAt = observedAt
        self.validUntil = validUntil
        self.provenance = provenance
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            placeID: container.decode(EntityID.self, forKey: .placeID),
            confidence: container.decode(Double.self, forKey: .confidence),
            observedAt: container.decode(Date.self, forKey: .observedAt),
            validUntil: container.decode(Date.self, forKey: .validUntil),
            provenance: container.decodeIfPresent([ProvenanceReference].self, forKey: .provenance)
                ?? []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case confidence
        case observedAt = "observed_at"
        case validUntil = "valid_until"
        case provenance
    }
}

public struct PersonUtterance: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var utteranceID: UtteranceID
    public var conversationID: ConversationID
    public var speakerID: EntityID
    public var addresseeIDs: [EntityID]
    public var inResponseToResponseID: ResponseID?
    public var text: String
    public var modality: UtteranceModality
    public var source: UtteranceSource
    public var sourceID: SourceID
    public var occurredAt: Date
    public var receivedAt: Date?
    public var confidence: Double
    public var placeEvidence: UtterancePlaceEvidence?
    public var causedBy: [ProvenanceReference]
    public var trace: W3CTraceContext?

    public init(
        utteranceID: UtteranceID = .generated(),
        conversationID: ConversationID,
        speakerID: EntityID,
        addresseeIDs: [EntityID],
        inResponseToResponseID: ResponseID? = nil,
        text: String,
        modality: UtteranceModality,
        source: UtteranceSource,
        sourceID: SourceID,
        occurredAt: Date,
        receivedAt: Date? = nil,
        confidence: Double,
        placeEvidence: UtterancePlaceEvidence? = nil,
        causedBy: [ProvenanceReference] = [],
        trace: W3CTraceContext? = nil
    ) throws {
        try validateConversationText(text)
        guard addresseeIDs.count == 1, confidence.isFinite, (0...1).contains(confidence) else {
            throw WorldContractError.invalidPersonUtterance
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.utteranceID = utteranceID
        self.conversationID = conversationID
        self.speakerID = speakerID
        self.addresseeIDs = addresseeIDs
        self.inResponseToResponseID = inResponseToResponseID
        self.text = text
        self.modality = modality
        self.source = source
        self.sourceID = sourceID
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.confidence = confidence
        self.placeEvidence = placeEvidence
        self.causedBy = causedBy
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            utteranceID: container.decode(UtteranceID.self, forKey: .utteranceID),
            conversationID: container.decode(ConversationID.self, forKey: .conversationID),
            speakerID: container.decode(EntityID.self, forKey: .speakerID),
            addresseeIDs: container.decode([EntityID].self, forKey: .addresseeIDs),
            inResponseToResponseID: container.decodeIfPresent(
                ResponseID.self,
                forKey: .inResponseToResponseID
            ),
            text: container.decode(String.self, forKey: .text),
            modality: container.decode(UtteranceModality.self, forKey: .modality),
            source: container.decode(UtteranceSource.self, forKey: .source),
            sourceID: container.decode(SourceID.self, forKey: .sourceID),
            occurredAt: container.decode(Date.self, forKey: .occurredAt),
            receivedAt: container.decodeIfPresent(Date.self, forKey: .receivedAt),
            confidence: container.decode(Double.self, forKey: .confidence),
            placeEvidence: container.decodeIfPresent(
                UtterancePlaceEvidence.self,
                forKey: .placeEvidence
            ),
            causedBy: container.decodeIfPresent([ProvenanceReference].self, forKey: .causedBy)
                ?? [],
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    /// Whether two records describe the same utterance. Trace context and receipt time are
    /// transport facts: a retry carries a new `traceparent` and arrives at a new time, yet it is
    /// still the same words from the same person, and must be recognised as such.
    public func isSameUtterance(as other: PersonUtterance) -> Bool {
        var mine = self
        var theirs = other
        mine.trace = nil
        theirs.trace = nil
        mine.receivedAt = nil
        theirs.receivedAt = nil
        return mine == theirs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case utteranceID = "utterance_id"
        case conversationID = "conversation_id"
        case speakerID = "speaker_id"
        case addresseeIDs = "addressee_ids"
        case inResponseToResponseID = "in_response_to_response_id"
        case text
        case modality
        case source
        case sourceID = "source_id"
        case occurredAt = "occurred_at"
        case receivedAt = "received_at"
        case confidence
        case placeEvidence = "place_evidence"
        case causedBy = "caused_by"
        case trace
    }
}

public enum ConversationAuthorKind: String, Hashable, Sendable, Codable {
    case person
    case character
}

public struct ConversationItem: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var itemID: ConversationItemID
    public var conversationID: ConversationID
    public var authorID: EntityID
    public var authorKind: ConversationAuthorKind
    public var text: String
    public var createdAt: Date
    public var inReplyToItemID: ConversationItemID?
    public var utteranceID: UtteranceID?
    public var responseID: ResponseID?
    public var trace: W3CTraceContext?

    public init(
        itemID: ConversationItemID = .generated(),
        conversationID: ConversationID,
        authorID: EntityID,
        authorKind: ConversationAuthorKind,
        text: String,
        createdAt: Date,
        inReplyToItemID: ConversationItemID? = nil,
        utteranceID: UtteranceID? = nil,
        responseID: ResponseID? = nil,
        trace: W3CTraceContext? = nil
    ) throws {
        try validateConversationText(text)
        let hasExactlyOneOrigin = (utteranceID == nil) != (responseID == nil)
        let authorMatchesOrigin =
            (authorKind == .person && utteranceID != nil)
            || (authorKind == .character && responseID != nil)
        guard hasExactlyOneOrigin, authorMatchesOrigin else {
            throw WorldContractError.invalidConversationItem
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.itemID = itemID
        self.conversationID = conversationID
        self.authorID = authorID
        self.authorKind = authorKind
        self.text = text
        self.createdAt = createdAt
        self.inReplyToItemID = inReplyToItemID
        self.utteranceID = utteranceID
        self.responseID = responseID
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            itemID: container.decode(ConversationItemID.self, forKey: .itemID),
            conversationID: container.decode(ConversationID.self, forKey: .conversationID),
            authorID: container.decode(EntityID.self, forKey: .authorID),
            authorKind: container.decode(ConversationAuthorKind.self, forKey: .authorKind),
            text: container.decode(String.self, forKey: .text),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            inReplyToItemID: container.decodeIfPresent(
                ConversationItemID.self,
                forKey: .inReplyToItemID
            ),
            utteranceID: container.decodeIfPresent(UtteranceID.self, forKey: .utteranceID),
            responseID: container.decodeIfPresent(ResponseID.self, forKey: .responseID),
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case itemID = "item_id"
        case conversationID = "conversation_id"
        case authorID = "author_id"
        case authorKind = "author_kind"
        case text
        case createdAt = "created_at"
        case inReplyToItemID = "in_reply_to_item_id"
        case utteranceID = "utterance_id"
        case responseID = "response_id"
        case trace
    }
}

/// A bounded, ordered page of the canonical conversation shared by every Creature client.
public struct ConversationItemPage: Hashable, Sendable, Codable {
    public var items: [ConversationItem]
    public var nextItemID: ConversationItemID?
    public var hasMore: Bool

    public init(
        items: [ConversationItem],
        nextItemID: ConversationItemID?,
        hasMore: Bool
    ) {
        self.items = items
        self.nextItemID = nextItemID
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case nextItemID = "next_item_id"
        case hasMore = "has_more"
    }
}

public struct PersonUtterancePercept: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var considerationID: ConsiderationID
    public var characterID: EntityID
    public var utterance: PersonUtterance
    public var priorConversationItems: [ConversationItem]
    /// Set when the world opened a scene for this utterance: the character will be offered the
    /// floor there and must not answer on its own.
    public var sceneID: SceneID?

    public init(
        considerationID: ConsiderationID = .generated(),
        characterID: EntityID,
        utterance: PersonUtterance,
        priorConversationItems: [ConversationItem],
        sceneID: SceneID? = nil
    ) throws {
        guard priorConversationItems.count <= ConversationContractLimits.maximumContextItems else {
            throw WorldContractError.conversationContextTooLarge(
                maximumItems: ConversationContractLimits.maximumContextItems
            )
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.considerationID = considerationID
        self.characterID = characterID
        self.utterance = utterance
        self.priorConversationItems = priorConversationItems
        self.sceneID = sceneID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        let priorConversationItems =
            try container.decodeIfPresent(
                [ConversationItem].self,
                forKey: .priorConversationItems
            ) ?? []
        try self.init(
            considerationID: container.decode(ConsiderationID.self, forKey: .considerationID),
            characterID: container.decode(EntityID.self, forKey: .characterID),
            utterance: container.decode(PersonUtterance.self, forKey: .utterance),
            priorConversationItems: priorConversationItems,
            sceneID: container.decodeIfPresent(SceneID.self, forKey: .sceneID)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case considerationID = "consideration_id"
        case characterID = "character_id"
        case utterance
        case priorConversationItems = "prior_conversation_items"
        case sceneID = "scene_id"
    }
}

extension PersonUtterancePercept: WorldEventPayload {
    public static let eventType = WorldEventType(rawValue: "conversation.person_utterance")!
}

public struct CharacterUtteranceIntent: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var responseID: ResponseID
    public var conversationID: ConversationID
    public var characterID: EntityID
    public var recipientID: EntityID
    public var inResponseToUtteranceID: UtteranceID?
    public var text: String
    public var urgency: Double
    public var createdAt: Date
    public var expiresAt: Date?
    public var reasonReferences: [ProvenanceReference]
    public var trace: W3CTraceContext?

    public init(
        responseID: ResponseID = .generated(),
        conversationID: ConversationID,
        characterID: EntityID,
        recipientID: EntityID,
        inResponseToUtteranceID: UtteranceID? = nil,
        text: String,
        urgency: Double,
        createdAt: Date,
        expiresAt: Date? = nil,
        reasonReferences: [ProvenanceReference] = [],
        trace: W3CTraceContext? = nil
    ) throws {
        try validateConversationText(text)
        guard urgency.isFinite,
            (0...1).contains(urgency),
            expiresAt.map({ $0 >= createdAt }) ?? true
        else {
            throw WorldContractError.invalidCharacterUtteranceIntent
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.responseID = responseID
        self.conversationID = conversationID
        self.characterID = characterID
        self.recipientID = recipientID
        self.inResponseToUtteranceID = inResponseToUtteranceID
        self.text = text
        self.urgency = urgency
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.reasonReferences = reasonReferences
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            responseID: container.decode(ResponseID.self, forKey: .responseID),
            conversationID: container.decode(ConversationID.self, forKey: .conversationID),
            characterID: container.decode(EntityID.self, forKey: .characterID),
            recipientID: container.decode(EntityID.self, forKey: .recipientID),
            inResponseToUtteranceID: container.decodeIfPresent(
                UtteranceID.self,
                forKey: .inResponseToUtteranceID
            ),
            text: container.decode(String.self, forKey: .text),
            urgency: container.decode(Double.self, forKey: .urgency),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            expiresAt: container.decodeIfPresent(Date.self, forKey: .expiresAt),
            reasonReferences: container.decodeIfPresent(
                [ProvenanceReference].self,
                forKey: .reasonReferences
            ) ?? [],
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    /// Whether two records describe the same character turn, ignoring transport trace context.
    public func isSameIntent(as other: CharacterUtteranceIntent) -> Bool {
        var mine = self
        var theirs = other
        mine.trace = nil
        theirs.trace = nil
        return mine == theirs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case responseID = "response_id"
        case conversationID = "conversation_id"
        case characterID = "character_id"
        case recipientID = "recipient_id"
        case inResponseToUtteranceID = "in_response_to_utterance_id"
        case text
        case urgency
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case reasonReferences = "reason_references"
        case trace
    }
}

public enum PersonPresenceState: String, Hashable, Sendable, Codable {
    case home
    case away
    case unknown
}

public struct PersonPresence: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var personID: EntityID
    public var state: PersonPresenceState
    public var confidence: Double
    public var observedAt: Date
    public var validUntil: Date
    public var physicallyAudible: Bool
    public var placeID: EntityID?
    public var provenance: [ProvenanceReference]
    /// How the world came to believe this: `assumed` for a configured default, `inferred` when
    /// it is derived (or, with zero confidence, simply not known), `observed` for a sensor.
    public var basis: EpistemicType

    public init(
        personID: EntityID,
        state: PersonPresenceState,
        confidence: Double,
        observedAt: Date,
        validUntil: Date,
        physicallyAudible: Bool,
        placeID: EntityID? = nil,
        provenance: [ProvenanceReference] = [],
        basis: EpistemicType = .inferred
    ) throws {
        guard confidence.isFinite, (0...1).contains(confidence), validUntil >= observedAt else {
            throw WorldContractError.invalidPresenceEvidence
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.personID = personID
        self.state = state
        self.confidence = confidence
        self.observedAt = observedAt
        self.validUntil = validUntil
        self.physicallyAudible = physicallyAudible
        self.placeID = placeID
        self.provenance = provenance
        self.basis = basis
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            personID: container.decode(EntityID.self, forKey: .personID),
            state: container.decode(PersonPresenceState.self, forKey: .state),
            confidence: container.decode(Double.self, forKey: .confidence),
            observedAt: container.decode(Date.self, forKey: .observedAt),
            validUntil: container.decode(Date.self, forKey: .validUntil),
            physicallyAudible: container.decode(Bool.self, forKey: .physicallyAudible),
            placeID: container.decodeIfPresent(EntityID.self, forKey: .placeID),
            provenance: container.decodeIfPresent([ProvenanceReference].self, forKey: .provenance)
                ?? [],
            basis: container.decodeIfPresent(EpistemicType.self, forKey: .basis) ?? .inferred
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case personID = "person_id"
        case state
        case confidence
        case observedAt = "observed_at"
        case validUntil = "valid_until"
        case physicallyAudible = "physically_audible"
        case placeID = "place_id"
        case provenance
        case basis
    }
}

public enum CharacterDeliveryRoute: String, Hashable, Sendable, Codable {
    case physicalSpeech = "physical_speech"
    case communicator
}

public enum CommunicatorPrivacyMode: String, Hashable, Sendable, Codable {
    case notApplicable = "not_applicable"
    case preview
    case `private`
}

public enum CharacterDeliveryReason: String, Hashable, Sendable, Codable {
    case homeAndAudible = "home_and_audible"
    case confidentlyAway = "confidently_away"
    case presenceUncertain = "presence_uncertain"
}

public struct CharacterDeliveryDecision: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var attemptID: DeliveryAttemptID
    public var responseID: ResponseID
    public var route: CharacterDeliveryRoute
    public var privacyMode: CommunicatorPrivacyMode
    public var reason: CharacterDeliveryReason
    public var decidedAt: Date
    public var presence: PersonPresence

    public init(
        attemptID: DeliveryAttemptID = .generated(),
        responseID: ResponseID,
        route: CharacterDeliveryRoute,
        privacyMode: CommunicatorPrivacyMode,
        reason: CharacterDeliveryReason,
        decidedAt: Date,
        presence: PersonPresence
    ) throws {
        let isConsistent: Bool
        switch (route, privacyMode, reason) {
        case (.physicalSpeech, .notApplicable, .homeAndAudible):
            isConsistent =
                presence.state == .home
                && presence.physicallyAudible
        case (.communicator, .preview, .confidentlyAway):
            isConsistent = presence.state == .away
        case (.communicator, .private, .presenceUncertain):
            isConsistent = true
        default:
            isConsistent = false
        }
        guard isConsistent else {
            throw WorldContractError.inconsistentDeliveryDecision
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.attemptID = attemptID
        self.responseID = responseID
        self.route = route
        self.privacyMode = privacyMode
        self.reason = reason
        self.decidedAt = decidedAt
        self.presence = presence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            attemptID: container.decode(DeliveryAttemptID.self, forKey: .attemptID),
            responseID: container.decode(ResponseID.self, forKey: .responseID),
            route: container.decode(CharacterDeliveryRoute.self, forKey: .route),
            privacyMode: container.decode(CommunicatorPrivacyMode.self, forKey: .privacyMode),
            reason: container.decode(CharacterDeliveryReason.self, forKey: .reason),
            decidedAt: container.decode(Date.self, forKey: .decidedAt),
            presence: container.decode(PersonPresence.self, forKey: .presence)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case attemptID = "attempt_id"
        case responseID = "response_id"
        case route
        case privacyMode = "privacy_mode"
        case reason
        case decidedAt = "decided_at"
        case presence
    }
}

public enum CharacterDeliveryOutcomeState: String, Hashable, Sendable, Codable {
    case queued
    case accepted
    case performed
    case duplicate
    case failed
}

public struct CharacterDeliveryOutcome: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var attemptID: DeliveryAttemptID
    public var responseID: ResponseID
    public var route: CharacterDeliveryRoute
    public var state: CharacterDeliveryOutcomeState
    public var occurredAt: Date
    public var providerReference: String?
    public var errorCode: String?

    public init(
        attemptID: DeliveryAttemptID,
        responseID: ResponseID,
        route: CharacterDeliveryRoute,
        state: CharacterDeliveryOutcomeState,
        occurredAt: Date,
        providerReference: String? = nil,
        errorCode: String? = nil
    ) {
        self.schemaVersion = WorldSchema.currentVersion
        self.attemptID = attemptID
        self.responseID = responseID
        self.route = route
        self.state = state
        self.occurredAt = occurredAt
        self.providerReference = providerReference
        self.errorCode = errorCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        self.schemaVersion = schemaVersion
        self.attemptID = try container.decode(DeliveryAttemptID.self, forKey: .attemptID)
        self.responseID = try container.decode(ResponseID.self, forKey: .responseID)
        self.route = try container.decode(CharacterDeliveryRoute.self, forKey: .route)
        self.state = try container.decode(CharacterDeliveryOutcomeState.self, forKey: .state)
        self.occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        self.providerReference = try container.decodeIfPresent(
            String.self,
            forKey: .providerReference
        )
        self.errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case attemptID = "attempt_id"
        case responseID = "response_id"
        case route
        case state
        case occurredAt = "occurred_at"
        case providerReference = "provider_reference"
        case errorCode = "error_code"
    }
}

/// One character turn as the world carried it: what the character wanted to say, where the
/// router decided it could be heard, what happened, and the canonical item in the shared history.
/// This is the read shape for viewers; the world's own durable record keeps its storage layout.
public struct CharacterDeliveryRecord: Hashable, Sendable, Codable {
    public var intent: CharacterUtteranceIntent
    public var decision: CharacterDeliveryDecision
    public var outcome: CharacterDeliveryOutcome?
    public var conversationItem: ConversationItem

    public init(
        intent: CharacterUtteranceIntent,
        decision: CharacterDeliveryDecision,
        outcome: CharacterDeliveryOutcome?,
        conversationItem: ConversationItem
    ) {
        self.intent = intent
        self.decision = decision
        self.outcome = outcome
        self.conversationItem = conversationItem
    }

    private enum CodingKeys: String, CodingKey {
        case intent
        case decision
        case outcome
        case conversationItem = "conversation_item"
    }
}

/// A bounded, ordered page of character deliveries in one conversation.
public struct CharacterDeliveryPage: Hashable, Sendable, Codable {
    public var deliveries: [CharacterDeliveryRecord]
    public var nextResponseID: ResponseID?
    public var hasMore: Bool

    public init(deliveries: [CharacterDeliveryRecord], nextResponseID: ResponseID?, hasMore: Bool) {
        self.deliveries = deliveries
        self.nextResponseID = nextResponseID
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case deliveries
        case nextResponseID = "next_response_id"
        case hasMore = "has_more"
    }
}

/// A mind asking the world where a turn it is about to produce should be performed.
public struct CharacterStageRequest: Hashable, Sendable, Codable {
    public var responseID: ResponseID
    public var characterID: EntityID
    public var recipientID: EntityID
    /// The session the asking mind holds for this character. Required once any mind is logged
    /// in as the character; a mind without the live session is told it is logged in elsewhere.
    public var sessionID: CharacterSessionID?

    public init(
        responseID: ResponseID,
        characterID: EntityID,
        recipientID: EntityID,
        sessionID: CharacterSessionID? = nil
    ) {
        self.responseID = responseID
        self.characterID = characterID
        self.recipientID = recipientID
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
        case characterID = "character_id"
        case recipientID = "recipient_id"
        case sessionID = "session_id"
    }
}

public enum CharacterStageDisposition: String, Hashable, Sendable, Codable {
    /// The world decided (or had already decided) the stage; the mind may perform on it.
    case decided
    /// This turn was already carried and has an outcome; the mind must not perform it again.
    case alreadyDelivered = "already_delivered"
}

/// The world's answer to a stage request.
public struct CharacterStageResult: Hashable, Sendable, Codable {
    public var disposition: CharacterStageDisposition
    public var decision: CharacterDeliveryDecision
    public var delivery: CharacterDeliveryRecord?

    public init(
        disposition: CharacterStageDisposition,
        decision: CharacterDeliveryDecision,
        delivery: CharacterDeliveryRecord? = nil
    ) {
        self.disposition = disposition
        self.decision = decision
        self.delivery = delivery
    }
}

/// What happened when a mind performed a staged turn itself.
public struct CharacterPerformanceReport: Hashable, Sendable, Codable {
    public var state: CharacterDeliveryOutcomeState
    public var providerReference: String?
    public var errorCode: String?

    public init(
        state: CharacterDeliveryOutcomeState,
        providerReference: String? = nil,
        errorCode: String? = nil
    ) throws {
        guard state == .performed || state == .failed else {
            throw WorldContractError.invalidPerformanceReport
        }
        self.state = state
        self.providerReference = providerReference
        self.errorCode = errorCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            state: container.decode(CharacterDeliveryOutcomeState.self, forKey: .state),
            providerReference: container.decodeIfPresent(String.self, forKey: .providerReference),
            errorCode: container.decodeIfPresent(String.self, forKey: .errorCode)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case providerReference = "provider_reference"
        case errorCode = "error_code"
    }
}

/// A performed turn: the words, the stage decision it was performed on, and how it went.
public struct CharacterPerformance: Hashable, Sendable, Codable {
    public var intent: CharacterUtteranceIntent
    public var attemptID: DeliveryAttemptID
    public var outcome: CharacterPerformanceReport
    public var sessionID: CharacterSessionID?

    public init(
        intent: CharacterUtteranceIntent,
        attemptID: DeliveryAttemptID,
        outcome: CharacterPerformanceReport,
        sessionID: CharacterSessionID? = nil
    ) {
        self.intent = intent
        self.attemptID = attemptID
        self.outcome = outcome
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case intent
        case attemptID = "attempt_id"
        case outcome
        case sessionID = "session_id"
    }
}

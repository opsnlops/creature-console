import Foundation

public struct PerceivedEvent: Hashable, Sendable, Codable {
    public var eventID: EventID
    public var type: WorldEventType

    public init(eventID: EventID, type: WorldEventType) {
        self.eventID = eventID
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case type
    }
}

public struct PerceptualFact: Hashable, Sendable, Codable {
    public var statement: String
    public var confidence: Double
    public var factID: FactID

    public init(statement: String, confidence: Double, factID: FactID) throws {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw WorldContractError.invalidConfidence(confidence)
        }
        self.statement = statement
        self.confidence = confidence
        self.factID = factID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            statement: container.decode(String.self, forKey: .statement),
            confidence: container.decode(Double.self, forKey: .confidence),
            factID: container.decode(FactID.self, forKey: .factID)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case statement
        case confidence
        case factID = "fact_id"
    }
}

public struct RelevantMemory: Hashable, Sendable, Codable {
    public var memoryID: MemoryID
    public var summary: String

    public init(memoryID: MemoryID, summary: String) {
        self.memoryID = memoryID
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case summary
    }
}

public struct PerceptualEnvelope: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var considerationID: ConsiderationID
    public var characterID: EntityID
    public var trace: W3CTraceContext?
    public var event: PerceivedEvent
    public var worldFacts: [PerceptualFact]
    public var relevantMemories: [RelevantMemory]
    public var knownParticipants: [EntityID]
    public var priorReactionInteractionIDs: [InteractionID]

    public init(
        considerationID: ConsiderationID = .generated(),
        characterID: EntityID,
        trace: W3CTraceContext? = nil,
        event: PerceivedEvent,
        worldFacts: [PerceptualFact],
        relevantMemories: [RelevantMemory],
        knownParticipants: [EntityID] = [],
        priorReactionInteractionIDs: [InteractionID] = []
    ) {
        self.schemaVersion = WorldSchema.currentVersion
        self.considerationID = considerationID
        self.characterID = characterID
        self.trace = trace
        self.event = event
        self.worldFacts = worldFacts
        self.relevantMemories = relevantMemories
        self.knownParticipants = knownParticipants
        self.priorReactionInteractionIDs = priorReactionInteractionIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        self.schemaVersion = schemaVersion
        self.considerationID = try container.decode(
            ConsiderationID.self,
            forKey: .considerationID
        )
        self.characterID = try container.decode(EntityID.self, forKey: .characterID)
        self.trace = try container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        self.event = try container.decode(PerceivedEvent.self, forKey: .event)
        self.worldFacts = try container.decode([PerceptualFact].self, forKey: .worldFacts)
        self.relevantMemories = try container.decode(
            [RelevantMemory].self,
            forKey: .relevantMemories
        )
        self.knownParticipants =
            try container.decodeIfPresent(
                [EntityID].self,
                forKey: .knownParticipants
            ) ?? []
        self.priorReactionInteractionIDs =
            try container.decodeIfPresent(
                [InteractionID].self,
                forKey: .priorReactionInteractionIDs
            ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case considerationID = "consideration_id"
        case characterID = "character_id"
        case trace
        case event
        case worldFacts = "world_facts"
        case relevantMemories = "relevant_memories"
        case knownParticipants = "known_participants"
        case priorReactionInteractionIDs = "prior_reaction_interaction_ids"
    }
}

public struct AgentDecision: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var considerationID: ConsiderationID
    public var characterID: EntityID
    public var wantsToReact: Bool
    public var confidence: Double
    public var intent: String?
    public var participants: [EntityID]
    public var urgency: Double
    public var suppressionReason: String?
    public var trace: W3CTraceContext?

    public init(
        considerationID: ConsiderationID,
        characterID: EntityID,
        wantsToReact: Bool,
        confidence: Double,
        intent: String? = nil,
        participants: [EntityID] = [],
        urgency: Double,
        suppressionReason: String? = nil,
        trace: W3CTraceContext? = nil
    ) throws {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw WorldContractError.invalidConfidence(confidence)
        }
        guard urgency.isFinite, (0...1).contains(urgency) else {
            throw WorldContractError.invalidConfidence(urgency)
        }
        let hasIntent = intent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard wantsToReact ? hasIntent && !participants.isEmpty : !hasIntent else {
            throw WorldContractError.inconsistentAgentDecision
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.considerationID = considerationID
        self.characterID = characterID
        self.wantsToReact = wantsToReact
        self.confidence = confidence
        self.intent = intent
        self.participants = participants
        self.urgency = urgency
        self.suppressionReason = suppressionReason
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            considerationID: container.decode(ConsiderationID.self, forKey: .considerationID),
            characterID: container.decode(EntityID.self, forKey: .characterID),
            wantsToReact: container.decode(Bool.self, forKey: .wantsToReact),
            confidence: container.decode(Double.self, forKey: .confidence),
            intent: container.decodeIfPresent(String.self, forKey: .intent),
            participants: container.decodeIfPresent([EntityID].self, forKey: .participants) ?? [],
            urgency: container.decode(Double.self, forKey: .urgency),
            suppressionReason: container.decodeIfPresent(
                String.self,
                forKey: .suppressionReason
            ),
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case considerationID = "consideration_id"
        case characterID = "character_id"
        case wantsToReact = "wants_to_react"
        case confidence
        case intent
        case participants
        case urgency
        case suppressionReason = "suppression_reason"
        case trace
    }
}

public enum PerformanceIntentKind: String, Hashable, Sendable, Codable {
    case dialog
    case animation
}

public struct PerformanceTurn: Hashable, Sendable, Codable {
    public var characterID: EntityID
    public var text: String

    public init(characterID: EntityID, text: String) {
        self.characterID = characterID
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case text
    }
}

public struct PerformanceIntent: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var intentID: IntentID
    public var considerationID: ConsiderationID
    public var interactionID: InteractionID
    public var characterID: EntityID
    public var kind: PerformanceIntentKind
    public var participants: [EntityID]
    public var turns: [PerformanceTurn]
    public var animationID: String?
    public var urgency: Double
    public var expiresAt: Date?
    public var trace: W3CTraceContext?

    public init(
        intentID: IntentID = .generated(),
        considerationID: ConsiderationID,
        interactionID: InteractionID = .generated(),
        characterID: EntityID,
        kind: PerformanceIntentKind,
        participants: [EntityID],
        turns: [PerformanceTurn] = [],
        animationID: String? = nil,
        urgency: Double,
        expiresAt: Date? = nil,
        trace: W3CTraceContext? = nil
    ) throws {
        guard urgency.isFinite, (0...1).contains(urgency) else {
            throw WorldContractError.invalidConfidence(urgency)
        }
        let participantSet = Set(participants)
        let participantsAreConsistent =
            participantSet.contains(characterID)
            && turns.allSatisfy { participantSet.contains($0.characterID) }
        let shapeIsValid: Bool
        switch kind {
        case .dialog:
            shapeIsValid = !turns.isEmpty && animationID == nil
        case .animation:
            shapeIsValid =
                turns.isEmpty
                && animationID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard participantsAreConsistent, shapeIsValid else {
            throw WorldContractError.invalidPerformanceIntent
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.intentID = intentID
        self.considerationID = considerationID
        self.interactionID = interactionID
        self.characterID = characterID
        self.kind = kind
        self.participants = participants
        self.turns = turns
        self.animationID = animationID
        self.urgency = urgency
        self.expiresAt = expiresAt
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            intentID: container.decode(IntentID.self, forKey: .intentID),
            considerationID: container.decode(ConsiderationID.self, forKey: .considerationID),
            interactionID: container.decode(InteractionID.self, forKey: .interactionID),
            characterID: container.decode(EntityID.self, forKey: .characterID),
            kind: container.decode(PerformanceIntentKind.self, forKey: .kind),
            participants: container.decode([EntityID].self, forKey: .participants),
            turns: container.decodeIfPresent([PerformanceTurn].self, forKey: .turns) ?? [],
            animationID: container.decodeIfPresent(String.self, forKey: .animationID),
            urgency: container.decode(Double.self, forKey: .urgency),
            expiresAt: container.decodeIfPresent(Date.self, forKey: .expiresAt),
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case intentID = "intent_id"
        case considerationID = "consideration_id"
        case interactionID = "interaction_id"
        case characterID = "character_id"
        case kind
        case participants
        case turns
        case animationID = "animation_id"
        case urgency
        case expiresAt = "expires_at"
        case trace
    }
}

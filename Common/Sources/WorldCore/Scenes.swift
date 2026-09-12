import Foundation
import Tracing

/// What set a scene going: something April said, or something that happened in the world.
public struct SceneTrigger: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case personUtterance = "person_utterance"
        case worldEvent = "world_event"
    }

    public var kind: Kind
    public var eventID: EventID
    public var utteranceID: UtteranceID?
    public var speakerID: EntityID?
    /// The character the trigger was addressed to, who gets the floor first.
    public var addresseeID: EntityID?
    /// The text a mind should react to: the utterance, or a sentence describing the event.
    public var text: String

    public init(
        kind: Kind,
        eventID: EventID,
        utteranceID: UtteranceID? = nil,
        speakerID: EntityID? = nil,
        addresseeID: EntityID? = nil,
        text: String
    ) {
        self.kind = kind
        self.eventID = eventID
        self.utteranceID = utteranceID
        self.speakerID = speakerID
        self.addresseeID = addresseeID
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case eventID = "event_id"
        case utteranceID = "utterance_id"
        case speakerID = "speaker_id"
        case addresseeID = "addressee_id"
        case text
    }
}

/// One character's answer when offered the floor: words, or a pass.
public struct SceneTurn: Hashable, Sendable, Codable {
    public var characterID: EntityID
    public var responseID: ResponseID
    /// `nil` is a pass: the character had nothing to add this time.
    public var text: String?
    public var offeredAt: Date
    public var answeredAt: Date
    public var conversationItemID: ConversationItemID?

    public init(
        characterID: EntityID,
        responseID: ResponseID,
        text: String?,
        offeredAt: Date,
        answeredAt: Date,
        conversationItemID: ConversationItemID? = nil
    ) {
        self.characterID = characterID
        self.responseID = responseID
        self.text = text
        self.offeredAt = offeredAt
        self.answeredAt = answeredAt
        self.conversationItemID = conversationItemID
    }

    public var isPass: Bool { text == nil }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case responseID = "response_id"
        case text
        case offeredAt = "offered_at"
        case answeredAt = "answered_at"
        case conversationItemID = "conversation_item_id"
    }
}

public enum SceneState: String, Hashable, Sendable, Codable {
    /// The floor is with someone; turns are still being composed.
    case open
    /// Composition is over; the performance is being rendered.
    case rendering
    case performed
    /// Nobody said anything, or the performance could not happen.
    case abandoned
}

public enum SceneCloseReason: String, Hashable, Sendable, Codable {
    /// Everyone present passed in a row.
    case everyonePassed = "everyone_passed"
    case maximumTurns = "maximum_turns"
    case maximumSpokenSeconds = "maximum_spoken_seconds"
    /// A person spoke again; the scene yields to the new exchange.
    case interrupted
}

/// Who holds the floor right now, and until when.
public struct SceneFloor: Hashable, Sendable, Codable {
    public var characterID: EntityID
    public var responseID: ResponseID
    public var offeredAt: Date
    public var deadline: Date

    public init(characterID: EntityID, responseID: ResponseID, offeredAt: Date, deadline: Date) {
        self.characterID = characterID
        self.responseID = responseID
        self.offeredAt = offeredAt
        self.deadline = deadline
    }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case responseID = "response_id"
        case offeredAt = "offered_at"
        case deadline
    }
}

/// How a scene was carried into the room.
public struct ScenePerformance: Hashable, Sendable, Codable {
    public var state: CharacterDeliveryOutcomeState
    public var providerReference: String?
    public var errorCode: String?
    public var occurredAt: Date

    public init(
        state: CharacterDeliveryOutcomeState,
        providerReference: String? = nil,
        errorCode: String? = nil,
        occurredAt: Date
    ) {
        self.state = state
        self.providerReference = providerReference
        self.errorCode = errorCode
        self.occurredAt = occurredAt
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case providerReference = "provider_reference"
        case errorCode = "error_code"
        case occurredAt = "occurred_at"
    }
}

/// A multi-party exchange the world coordinates: who is in it, whose turn it is, what has been
/// said, and how it was performed. Minds compose; the world gives the floor and keeps the record.
public struct Scene: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public var sceneID: SceneID
    public var regionID: EntityID
    public var conversationID: ConversationID
    public var trigger: SceneTrigger
    public var participants: [EntityID]
    public var turns: [SceneTurn]
    public var floor: SceneFloor?
    public var state: SceneState
    public var closeReason: SceneCloseReason?
    public var openedAt: Date
    public var closedAt: Date?
    public var performance: ScenePerformance?
    public var trace: W3CTraceContext?

    public init(
        sceneID: SceneID = .generated(),
        regionID: EntityID,
        conversationID: ConversationID,
        trigger: SceneTrigger,
        participants: [EntityID],
        turns: [SceneTurn] = [],
        floor: SceneFloor? = nil,
        state: SceneState = .open,
        closeReason: SceneCloseReason? = nil,
        openedAt: Date,
        closedAt: Date? = nil,
        performance: ScenePerformance? = nil,
        trace: W3CTraceContext? = nil
    ) throws {
        guard participants.count >= 1, Set(participants).count == participants.count else {
            throw WorldContractError.invalidScene
        }
        self.schemaVersion = WorldSchema.currentVersion
        self.sceneID = sceneID
        self.regionID = regionID
        self.conversationID = conversationID
        self.trigger = trigger
        self.participants = participants
        self.turns = turns
        self.floor = floor
        self.state = state
        self.closeReason = closeReason
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.performance = performance
        self.trace = trace
    }

    public var spokenTurns: [SceneTurn] { turns.filter { !$0.isPass } }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try WorldSchema.validate(schemaVersion)
        try self.init(
            sceneID: container.decode(SceneID.self, forKey: .sceneID),
            regionID: container.decode(EntityID.self, forKey: .regionID),
            conversationID: container.decode(ConversationID.self, forKey: .conversationID),
            trigger: container.decode(SceneTrigger.self, forKey: .trigger),
            participants: container.decode([EntityID].self, forKey: .participants),
            turns: container.decodeIfPresent([SceneTurn].self, forKey: .turns) ?? [],
            floor: container.decodeIfPresent(SceneFloor.self, forKey: .floor),
            state: container.decode(SceneState.self, forKey: .state),
            closeReason: container.decodeIfPresent(SceneCloseReason.self, forKey: .closeReason),
            openedAt: container.decode(Date.self, forKey: .openedAt),
            closedAt: container.decodeIfPresent(Date.self, forKey: .closedAt),
            performance: container.decodeIfPresent(ScenePerformance.self, forKey: .performance),
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sceneID = "scene_id"
        case regionID = "region_id"
        case conversationID = "conversation_id"
        case trigger
        case participants
        case turns
        case floor
        case state
        case closeReason = "close_reason"
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case performance
        case trace
    }
}

/// What a mind sees when the world offers it the floor.
public struct SceneTurnOffer: Hashable, Sendable, Codable {
    public var sceneID: SceneID
    public var characterID: EntityID
    public var responseID: ResponseID
    public var deadline: Date
    public var trigger: SceneTrigger
    public var participants: [EntityID]
    public var turns: [SceneTurn]
    /// What the world knows that bears on the scene, for this character.
    public var worldFacts: [Fact]

    public init(
        sceneID: SceneID,
        characterID: EntityID,
        responseID: ResponseID,
        deadline: Date,
        trigger: SceneTrigger,
        participants: [EntityID],
        turns: [SceneTurn],
        worldFacts: [Fact] = []
    ) {
        self.sceneID = sceneID
        self.characterID = characterID
        self.responseID = responseID
        self.deadline = deadline
        self.trigger = trigger
        self.participants = participants
        self.turns = turns
        self.worldFacts = worldFacts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sceneID: try container.decode(SceneID.self, forKey: .sceneID),
            characterID: try container.decode(EntityID.self, forKey: .characterID),
            responseID: try container.decode(ResponseID.self, forKey: .responseID),
            deadline: try container.decode(Date.self, forKey: .deadline),
            trigger: try container.decode(SceneTrigger.self, forKey: .trigger),
            participants: try container.decode([EntityID].self, forKey: .participants),
            turns: try container.decode([SceneTurn].self, forKey: .turns),
            worldFacts: try container.decodeIfPresent([Fact].self, forKey: .worldFacts) ?? []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sceneID = "scene_id"
        case characterID = "character_id"
        case responseID = "response_id"
        case deadline
        case trigger
        case participants
        case turns
        case worldFacts = "world_facts"
    }
}

extension SceneTurnOffer: WorldEventPayload {
    public static let eventType = WorldEventType(rawValue: "scene.turn_offered")!
}

/// A mind's answer to an offer.
public struct SceneTurnSubmission: Hashable, Sendable, Codable {
    public var characterID: EntityID
    public var responseID: ResponseID
    public var sessionID: CharacterSessionID?
    /// `nil` passes the floor.
    public var text: String?
    public var trace: W3CTraceContext?

    public init(
        characterID: EntityID,
        responseID: ResponseID,
        sessionID: CharacterSessionID? = nil,
        text: String?,
        trace: W3CTraceContext? = nil
    ) throws {
        if let text {
            try validateConversationText(text)
        }
        self.characterID = characterID
        self.responseID = responseID
        self.sessionID = sessionID
        self.text = text
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            characterID: container.decode(EntityID.self, forKey: .characterID),
            responseID: container.decode(ResponseID.self, forKey: .responseID),
            sessionID: container.decodeIfPresent(CharacterSessionID.self, forKey: .sessionID),
            text: container.decodeIfPresent(String.self, forKey: .text),
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case responseID = "response_id"
        case sessionID = "session_id"
        case text
        case trace
    }
}

public enum SceneTurnDisposition: String, Hashable, Sendable, Codable {
    case accepted
    /// The same response was already recorded.
    case duplicate
    /// The floor was not this character's (it moved on, or was never theirs).
    case notYourTurn = "not_your_turn"
}

public struct SceneTurnResult: Hashable, Sendable, Codable {
    public var disposition: SceneTurnDisposition
    public var scene: Scene

    public init(disposition: SceneTurnDisposition, scene: Scene) {
        self.disposition = disposition
        self.scene = scene
    }
}

public struct ScenePage: Hashable, Sendable, Codable {
    public var scenes: [Scene]

    public init(scenes: [Scene]) {
        self.scenes = scenes
    }
}

/// Where the world keeps its cutoffs for a scene, so April can tune the feel.
public struct SceneLimits: Hashable, Sendable, Codable {
    public var floorSeconds: TimeInterval
    public var maximumTurns: Int
    public var maximumSpokenSeconds: TimeInterval
    /// Rough reading pace used to estimate spoken time from text.
    public var wordsPerSecond: Double

    public init(
        floorSeconds: TimeInterval = 8,
        maximumTurns: Int = 12,
        maximumSpokenSeconds: TimeInterval = 90,
        wordsPerSecond: Double = 2.5
    ) {
        self.floorSeconds = floorSeconds
        self.maximumTurns = maximumTurns
        self.maximumSpokenSeconds = maximumSpokenSeconds
        self.wordsPerSecond = wordsPerSecond
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SceneLimits()
        self.init(
            floorSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .floorSeconds)
                ?? defaults.floorSeconds,
            maximumTurns: try container.decodeIfPresent(Int.self, forKey: .maximumTurns)
                ?? defaults.maximumTurns,
            maximumSpokenSeconds: try container.decodeIfPresent(
                TimeInterval.self, forKey: .maximumSpokenSeconds)
                ?? defaults.maximumSpokenSeconds,
            wordsPerSecond: try container.decodeIfPresent(Double.self, forKey: .wordsPerSecond)
                ?? defaults.wordsPerSecond
        )
    }

    public func spokenSeconds(of text: String) -> TimeInterval {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return Double(words) / max(wordsPerSecond, 0.1)
    }

    private enum CodingKeys: String, CodingKey {
        case floorSeconds = "floor_seconds"
        case maximumTurns = "maximum_turns"
        case maximumSpokenSeconds = "maximum_spoken_seconds"
        case wordsPerSecond = "words_per_second"
    }
}

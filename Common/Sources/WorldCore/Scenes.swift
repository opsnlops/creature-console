import Foundation
import Tracing

/// What set a scene going: something April said, or something that happened in the world.
public struct SceneTrigger: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case personUtterance = "person_utterance"
        /// The house noticed something the lead must say (an `open_on` rule).
        case worldEvent = "world_event"
        /// The house noticed something the lead may say — or may judge not worth a word
        /// (a `consider_on` rule). Step 3 of the judgement plan: the model decides what
        /// deserves a word; the world keeps the guardrails and records the choice.
        case houseConsideration = "house_consideration"
    }

    /// The house started this, one way or the other.
    public var isHouseOccasion: Bool { kind == .worldEvent || kind == .houseConsideration }

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
    /// Why a pass, when the mind said (a house consideration it judged not worth a word).
    public var quietReason: String?

    public init(
        characterID: EntityID,
        responseID: ResponseID,
        text: String?,
        offeredAt: Date,
        answeredAt: Date,
        conversationItemID: ConversationItemID? = nil,
        quietReason: String? = nil
    ) {
        self.characterID = characterID
        self.responseID = responseID
        self.text = text
        self.offeredAt = offeredAt
        self.answeredAt = answeredAt
        self.conversationItemID = conversationItemID
        self.quietReason = quietReason
    }

    public var isPass: Bool { text == nil }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case responseID = "response_id"
        case text
        case offeredAt = "offered_at"
        case answeredAt = "answered_at"
        case conversationItemID = "conversation_item_id"
        case quietReason = "quiet_reason"
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
    /// Everyone had a turn and the last line asked for nothing more.
    case roundDone = "round_done"
    case maximumTurns = "maximum_turns"
    case maximumSpokenSeconds = "maximum_spoken_seconds"
    /// A person spoke again; the scene yields to the new exchange.
    case interrupted
    /// The house asked and the lead judged it not worth a word.
    case declined
}

/// Who holds the floor right now, and until when.
public struct SceneFloor: Hashable, Sendable, Codable {
    public var characterID: EntityID
    public var responseID: ResponseID
    public var offeredAt: Date
    public var deadline: Date
    /// The sentences of the line so far, when the mind is streaming its turn: each one is
    /// spoken as it lands, and the whole becomes the turn when the mind says it is done.
    public var pieces: [String]

    public init(
        characterID: EntityID, responseID: ResponseID, offeredAt: Date, deadline: Date,
        pieces: [String] = []
    ) {
        self.characterID = characterID
        self.responseID = responseID
        self.offeredAt = offeredAt
        self.deadline = deadline
        self.pieces = pieces
    }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case responseID = "response_id"
        case offeredAt = "offered_at"
        case deadline
        case pieces
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        characterID = try container.decode(EntityID.self, forKey: .characterID)
        responseID = try container.decode(ResponseID.self, forKey: .responseID)
        offeredAt = try container.decode(Date.self, forKey: .offeredAt)
        deadline = try container.decode(Date.self, forKey: .deadline)
        pieces = try container.decodeIfPresent([String].self, forKey: .pieces) ?? []
    }
}

/// How a scene was carried into the room.
public struct ScenePerformance: Hashable, Sendable, Codable {
    public var state: CharacterDeliveryOutcomeState
    public var providerReference: String?
    public var errorCode: String?
    /// What went wrong, in Creature Server's words, so the Viewer can say it.
    public var errorMessage: String?
    public var occurredAt: Date

    public init(
        state: CharacterDeliveryOutcomeState,
        providerReference: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        occurredAt: Date
    ) {
        self.state = state
        self.providerReference = providerReference
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.occurredAt = occurredAt
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case providerReference = "provider_reference"
        case errorCode = "error_code"
        case errorMessage = "error_message"
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
    /// When the room is expected to finish saying what has been queued so far — the world's
    /// estimate from word count until Creature Server reports it — so the next floor is
    /// offered when the last line has been heard, not the moment it was composed.
    public var spokenUntil: Date?
    /// The next character in line while the room catches up.
    public var pendingFloor: EntityID?

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
        trace: W3CTraceContext? = nil,
        spokenUntil: Date? = nil,
        pendingFloor: EntityID? = nil
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
        self.spokenUntil = spokenUntil
        self.pendingFloor = pendingFloor
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
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace),
            spokenUntil: container.decodeIfPresent(Date.self, forKey: .spokenUntil),
            pendingFloor: container.decodeIfPresent(EntityID.self, forKey: .pendingFloor)
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
        case spokenUntil = "spoken_until"
        case pendingFloor = "pending_floor"
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
    /// What just happened around the scene: the story behind the facts, oldest first.
    public var recentHappenings: [Happening]
    /// What the facts' predicates mean, for the ones present.
    public var factMeanings: [String: String]

    public init(
        sceneID: SceneID,
        characterID: EntityID,
        responseID: ResponseID,
        deadline: Date,
        trigger: SceneTrigger,
        participants: [EntityID],
        turns: [SceneTurn],
        worldFacts: [Fact] = [],
        recentHappenings: [Happening] = [],
        factMeanings: [String: String] = [:]
    ) {
        self.sceneID = sceneID
        self.characterID = characterID
        self.responseID = responseID
        self.deadline = deadline
        self.trigger = trigger
        self.participants = participants
        self.turns = turns
        self.worldFacts = worldFacts
        self.recentHappenings = recentHappenings
        self.factMeanings = factMeanings
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
            worldFacts: try container.decodeIfPresent([Fact].self, forKey: .worldFacts) ?? [],
            recentHappenings: try container.decodeIfPresent(
                [Happening].self, forKey: .recentHappenings) ?? [],
            factMeanings: try container.decodeIfPresent(
                [String: String].self, forKey: .factMeanings) ?? [:]
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
        case recentHappenings = "recent_happenings"
        case factMeanings = "fact_meanings"
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
    /// The line, or one sentence of it when `piece` is set. `nil` with no piece passes the
    /// floor; `nil` after pieces were sent means "that was the whole line".
    public var text: String?
    /// The index of this sentence in a streamed line (0, 1, 2, …), so a retry is recognised;
    /// `nil` means the turn is complete with this submission.
    public var piece: Int?
    /// Why the floor is passed, when the house asked and the mind chose quiet — for the
    /// Viewer, never spoken.
    public var quietReason: String?
    public var trace: W3CTraceContext?

    public var isPartial: Bool { piece != nil }

    public init(
        characterID: EntityID,
        responseID: ResponseID,
        sessionID: CharacterSessionID? = nil,
        text: String?,
        piece: Int? = nil,
        quietReason: String? = nil,
        trace: W3CTraceContext? = nil
    ) throws {
        if let text {
            try validateConversationText(text)
        }
        if let piece {
            guard piece >= 0 else { throw WorldContractError.invalidScene }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorldContractError.invalidScene
            }
        }
        self.characterID = characterID
        self.responseID = responseID
        self.sessionID = sessionID
        self.text = text
        self.piece = piece
        self.quietReason = quietReason.map { String($0.prefix(200)) }
        self.trace = trace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            characterID: container.decode(EntityID.self, forKey: .characterID),
            responseID: container.decode(ResponseID.self, forKey: .responseID),
            sessionID: container.decodeIfPresent(CharacterSessionID.self, forKey: .sessionID),
            text: container.decodeIfPresent(String.self, forKey: .text),
            piece: container.decodeIfPresent(Int.self, forKey: .piece),
            quietReason: container.decodeIfPresent(String.self, forKey: .quietReason),
            trace: container.decodeIfPresent(W3CTraceContext.self, forKey: .trace)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case responseID = "response_id"
        case sessionID = "session_id"
        case text
        case piece
        case quietReason = "quiet_reason"
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

/// How fast one voice speaks. Measure it from Creature Server's `StreamingAdHocSession.sentence`
/// spans: `animation.frames` × 20 ms against `sentence.length`.
public struct SpeakingPace: Hashable, Sendable, Codable {
    public var charactersPerSecond: Double
    public var sentenceSeconds: TimeInterval

    public init(charactersPerSecond: Double, sentenceSeconds: TimeInterval) {
        self.charactersPerSecond = charactersPerSecond
        self.sentenceSeconds = sentenceSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case charactersPerSecond = "characters_per_second"
        case sentenceSeconds = "sentence_seconds"
    }
}

/// Where the world keeps its cutoffs for a scene, so April can tune the feel.
public struct SceneLimits: Hashable, Sendable, Codable {
    public var floorSeconds: TimeInterval
    public var maximumTurns: Int
    /// Turns in a scene the house opened. A visitor at the carport should get Beaky's
    /// remark and a reaction or two, not a twelve-turn debate: "I don't need Jesse coming
    /// over to turn into a debate about Arch vs Debian." April: "She can have others join
    /// her, but no more than three turns."
    public var houseMaximumTurns: Int
    public var maximumSpokenSeconds: TimeInterval
    /// How fast the room speaks, for estimating how long a line will play: characters a
    /// second once a sentence is under way, plus a fixed cost per sentence (the breath
    /// before it and the tail after). Fitted to Creature Server's rendered frame counts:
    /// twenty characters a second and a third of a second a sentence land within a tenth
    /// of a second of what ElevenLabs actually produced.
    public var charactersPerSecond: Double
    public var sentenceSeconds: TimeInterval
    /// Voices that speak at their own pace, by character ID. Kenny's voice drawls at about
    /// eleven characters a second where Beaky's and Mango's run twenty; without this the
    /// world thinks his lines are half as long as they are and the birds run ahead of the
    /// room.
    public var voices: [String: SpeakingPace]
    /// The world events that open a scene on their own, and where, and how often.
    public var openOn: [SceneOpeningRule]
    /// The world events the house *asks* the lead about: a scene opens, but the lead may
    /// judge it not worth a word and stay quiet, and the world records that.
    public var considerOn: [SceneOpeningRule]
    /// When the house does not wake the birds at all; nil means never quiet.
    public var quietHours: QuietHours?
    /// The least time between any two scenes the house opens, across all rules; zero (the
    /// default) lets every rule speak. April: "If I'm at home and watching TV I want to know
    /// that someone's out there sooner rather than later" — the updates as a visitor moves from
    /// the door to the driveway to the carport are the point, and Beaky already treats them as
    /// one event on her own.
    public var houseGapSeconds: TimeInterval
    /// How long before the room finishes the last line the next floor is offered, so the
    /// next bird's first sentence lands as the previous one ends: a first-sentence latency
    /// plus the render. A line that arrives early simply queues behind the one playing —
    /// Creature Server plays a scene's sentences in order — so the cost of a generous lead
    /// is only that April's interjection may land after the next line is already composed.
    public var turnLeadSeconds: TimeInterval

    public init(
        floorSeconds: TimeInterval = 8,
        maximumTurns: Int = 6,
        houseMaximumTurns: Int = 3,
        maximumSpokenSeconds: TimeInterval = 90,
        charactersPerSecond: Double = 20,
        sentenceSeconds: TimeInterval = 0.35,
        voices: [String: SpeakingPace] = [:],
        openOn: [SceneOpeningRule] = [],
        considerOn: [SceneOpeningRule] = [],
        houseGapSeconds: TimeInterval = 0,
        quietHours: QuietHours? = nil,
        turnLeadSeconds: TimeInterval = 2
    ) {
        self.floorSeconds = floorSeconds
        self.maximumTurns = maximumTurns
        self.houseMaximumTurns = houseMaximumTurns
        self.maximumSpokenSeconds = maximumSpokenSeconds
        self.charactersPerSecond = charactersPerSecond
        self.sentenceSeconds = sentenceSeconds
        self.voices = voices
        self.openOn = openOn
        self.considerOn = considerOn
        self.houseGapSeconds = houseGapSeconds
        self.quietHours = quietHours
        self.turnLeadSeconds = turnLeadSeconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SceneLimits()
        self.init(
            floorSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .floorSeconds)
                ?? defaults.floorSeconds,
            maximumTurns: try container.decodeIfPresent(Int.self, forKey: .maximumTurns)
                ?? defaults.maximumTurns,
            houseMaximumTurns: try container.decodeIfPresent(Int.self, forKey: .houseMaximumTurns)
                ?? defaults.houseMaximumTurns,
            maximumSpokenSeconds: try container.decodeIfPresent(
                TimeInterval.self, forKey: .maximumSpokenSeconds)
                ?? defaults.maximumSpokenSeconds,
            charactersPerSecond: try container.decodeIfPresent(
                Double.self, forKey: .charactersPerSecond) ?? defaults.charactersPerSecond,
            sentenceSeconds: try container.decodeIfPresent(
                TimeInterval.self, forKey: .sentenceSeconds) ?? defaults.sentenceSeconds,
            voices: try container.decodeIfPresent([String: SpeakingPace].self, forKey: .voices)
                ?? [:],
            openOn: try container.decodeIfPresent([SceneOpeningRule].self, forKey: .openOn) ?? [],
            considerOn: try container.decodeIfPresent(
                [SceneOpeningRule].self, forKey: .considerOn) ?? [],
            houseGapSeconds: try container.decodeIfPresent(
                TimeInterval.self, forKey: .houseGapSeconds) ?? defaults.houseGapSeconds,
            quietHours: try container.decodeIfPresent(QuietHours.self, forKey: .quietHours),
            turnLeadSeconds: try container.decodeIfPresent(
                TimeInterval.self, forKey: .turnLeadSeconds)
                ?? defaults.turnLeadSeconds
        )
    }

    /// How long the room will take to say `text` in `speaker`'s voice: a fixed cost per
    /// sentence plus the characters at that voice's pace. Nothing to say takes no time.
    public func spokenSeconds(of text: String, by speaker: EntityID? = nil) -> TimeInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let pace = pace(of: speaker)
        let sentences = max(1, trimmed.filter { ".!?".contains($0) }.count)
        return Double(sentences) * pace.sentenceSeconds
            + Double(trimmed.count) / max(pace.charactersPerSecond, 0.1)
    }

    public func pace(of speaker: EntityID?) -> SpeakingPace {
        if let speaker, let voice = voices[speaker.rawValue] { return voice }
        return SpeakingPace(
            charactersPerSecond: charactersPerSecond, sentenceSeconds: sentenceSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case floorSeconds = "floor_seconds"
        case maximumTurns = "maximum_turns"
        case houseMaximumTurns = "house_maximum_turns"
        case maximumSpokenSeconds = "maximum_spoken_seconds"
        case charactersPerSecond = "characters_per_second"
        case sentenceSeconds = "sentence_seconds"
        case voices
        case openOn = "open_on"
        case considerOn = "consider_on"
        case houseGapSeconds = "house_gap_seconds"
        case quietHours = "quiet_hours"
        case turnLeadSeconds = "turn_lead_seconds"
    }
}

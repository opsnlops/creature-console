import Foundation

/// Wire contracts of Creature World's `/world/v1` read API, shared by the simulator, World
/// Viewer, and the character mind. All keys are snake_case and every list is bounded.

public struct WorldHealth: Codable, Equatable, Sendable {
    public var status: String
    public var service: String
    public var buildVersion: String
    public var mongodb: String
    public var schemaVersion: Int

    public init(
        status: String, service: String, buildVersion: String, mongodb: String, schemaVersion: Int
    ) {
        self.status = status
        self.service = service
        self.buildVersion = buildVersion
        self.mongodb = mongodb
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case service
        case buildVersion = "build_version"
        case mongodb
        case schemaVersion = "schema_version"
    }
}

public struct WorldEventPage: Codable, Equatable, Sendable {
    public var events: [WorldEventEnvelope]
    public var nextSequence: Int64
    public var hasMore: Bool

    public init(events: [WorldEventEnvelope], nextSequence: Int64, hasMore: Bool) {
        self.events = events
        self.nextSequence = nextSequence
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case events
        case nextSequence = "next_sequence"
        case hasMore = "has_more"
    }
}

/// One day of the world, for a mind's nightly memory job: what happened, what was said, what
/// was cast. Human-readable pieces only; the job never sees raw payloads.
public struct DayDigest: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var at: Date
        public var who: String
        public var text: String

        public init(at: Date, who: String, text: String) {
            self.at = at
            self.who = who
            self.text = text
        }
    }

    public struct SceneLines: Codable, Equatable, Sendable {
        public var openedAt: Date
        public var trigger: String
        public var lines: [Line]

        public init(openedAt: Date, trigger: String, lines: [Line]) {
            self.openedAt = openedAt
            self.trigger = trigger
            self.lines = lines
        }

        private enum CodingKeys: String, CodingKey {
            case openedAt = "opened_at"
            case trigger, lines
        }
    }

    /// `2026-09-13`, in the house's zone.
    public var day: String
    public var timeZone: String
    public var happenings: [Happening]
    public var conversation: [Line]
    public var scenes: [SceneLines]
    /// What the world was told that day: "person:jesse visitor.expected = …" by whom.
    public var learned: [Line]

    public init(
        day: String, timeZone: String, happenings: [Happening], conversation: [Line],
        scenes: [SceneLines], learned: [Line]
    ) {
        self.day = day
        self.timeZone = timeZone
        self.happenings = happenings
        self.conversation = conversation
        self.scenes = scenes
        self.learned = learned
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case timeZone = "time_zone"
        case happenings, conversation, scenes, learned
    }
}

/// Who a kind of fact is for. `minds`: handed to the birds in their prompts (the default).
/// `world`: kept, shown in the Viewer, usable by the world's rules - never put in a prompt.
/// A phone number is `world`; a birthday is `minds`.
public enum FactAudience: String, Codable, Equatable, Sendable, CaseIterable {
    case minds
    case world
}

/// What a predicate means, as the world tells its minds, and who it is for. Seeded from
/// `WorldFacts.meanings`; a Wizard may reword it in the Viewer, and the world remembers who did.
public struct FactKind: Codable, Equatable, Sendable {
    public var predicate: String
    public var meaning: String
    public var audience: FactAudience
    public var updatedAt: Date
    public var updatedBy: String

    public init(
        predicate: String, meaning: String, audience: FactAudience = .minds, updatedAt: Date,
        updatedBy: String
    ) {
        self.predicate = predicate
        self.meaning = meaning
        self.audience = audience
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        predicate = try container.decode(String.self, forKey: .predicate)
        meaning = try container.decode(String.self, forKey: .meaning)
        audience = try container.decodeIfPresent(FactAudience.self, forKey: .audience) ?? .minds
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        updatedBy = try container.decode(String.self, forKey: .updatedBy)
    }

    private enum CodingKeys: String, CodingKey {
        case predicate
        case meaning
        case audience
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }
}

/// A Wizard's (or a source's) word on a kind: the meaning, and optionally who it is for. An
/// absent audience leaves the kind's audience as it is (`minds` for a new kind).
public struct FactKindUpdate: Codable, Equatable, Sendable {
    public var meaning: String
    public var audience: FactAudience?
    public var updatedBy: String

    public init(meaning: String, audience: FactAudience? = nil, updatedBy: String) {
        self.meaning = meaning
        self.audience = audience
        self.updatedBy = updatedBy
    }

    private enum CodingKeys: String, CodingKey {
        case meaning
        case audience
        case updatedBy = "updated_by"
    }
}

/// What a mind would be handed right now: the facts about a character, its region, and April,
/// with the mentions in `text` if any, the meanings of those kinds, and the story so far. The
/// WorldMCP `query_character_perspective` tool - the same knowledge a scene offer carries.
public struct CharacterPerspective: Codable, Hashable, Sendable {
    public var characterID: EntityID
    public var facts: [Fact]
    public var factMeanings: [String: String]
    public var recentHappenings: [Happening]

    public init(
        characterID: EntityID, facts: [Fact], factMeanings: [String: String],
        recentHappenings: [Happening]
    ) {
        self.characterID = characterID
        self.facts = facts
        self.factMeanings = factMeanings
        self.recentHappenings = recentHappenings
    }

    private enum CodingKeys: String, CodingKey {
        case characterID = "character_id"
        case facts
        case factMeanings = "fact_meanings"
        case recentHappenings = "recent_happenings"
    }
}

/// Why a fact is what it is: the fact, the events and facts it was derived from (walked a few
/// levels), and what superseded it, if anything. The WorldMCP `explain_fact` tool.
public struct FactExplanation: Codable, Hashable, Sendable {
    public var fact: Fact
    /// The events behind it, nearest first.
    public var events: [WorldEventEnvelope]
    /// Facts behind it (a derived fact's inputs), nearest first.
    public var facts: [Fact]
    public var supersededBy: Fact?

    public init(fact: Fact, events: [WorldEventEnvelope], facts: [Fact], supersededBy: Fact?) {
        self.fact = fact
        self.events = events
        self.facts = facts
        self.supersededBy = supersededBy
    }

    private enum CodingKeys: String, CodingKey {
        case fact, events, facts
        case supersededBy = "superseded_by"
    }
}

/// What a search found: an entity, how well it matched, and the current facts that matched -
/// so "the cleaner" answers with `person:tamara` and the relationship that said so, and a mind
/// often needs no second call.
public struct WorldSearchHit: Codable, Hashable, Sendable {
    public var entityID: EntityID
    public var score: Double
    public var facts: [Fact]

    public init(entityID: EntityID, score: Double, facts: [Fact]) {
        self.entityID = entityID
        self.score = score
        self.facts = facts
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case score, facts
    }
}

public struct WorldSearchPage: Codable, Hashable, Sendable {
    public var query: String
    public var hits: [WorldSearchHit]

    public init(query: String, hits: [WorldSearchHit]) {
        self.query = query
        self.hits = hits
    }
}

/// One entity, whole: what the world believes about it, what elsewhere points at it, and what
/// has happened around it lately. The Viewer's entity page, and a mind's "who is Jesse?".
public struct EntityPage: Codable, Hashable, Sendable {
    public var entityID: EntityID
    /// Current facts about the entity, every audience.
    public var facts: [Fact]
    /// Current facts elsewhere whose value is this entity: `calendar.with = person:jesse`.
    public var linkedFrom: [Fact]
    /// Recent events with the entity as a subject, newest first.
    public var events: [WorldEventEnvelope]

    public init(entityID: EntityID, facts: [Fact], linkedFrom: [Fact], events: [WorldEventEnvelope])
    {
        self.entityID = entityID
        self.facts = facts
        self.linkedFrom = linkedFrom
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case facts
        case linkedFrom = "linked_from"
        case events
    }
}

public struct FactKindPage: Codable, Equatable, Sendable {
    public var kinds: [FactKind]

    public init(kinds: [FactKind]) { self.kinds = kinds }
}

public struct WorldFactPage: Codable, Equatable, Sendable {
    public var facts: [Fact]
    public var nextFactID: FactID?
    public var hasMore: Bool

    public init(facts: [Fact], nextFactID: FactID?, hasMore: Bool) {
        self.facts = facts
        self.nextFactID = nextFactID
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case facts
        case nextFactID = "next_fact_id"
        case hasMore = "has_more"
    }
}

public struct WorldTimerPage: Codable, Equatable, Sendable {
    public var timers: [WorldTimer]
    public var nextTimerID: TimerID?
    public var hasMore: Bool

    public init(timers: [WorldTimer], nextTimerID: TimerID?, hasMore: Bool) {
        self.timers = timers
        self.nextTimerID = nextTimerID
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case timers
        case nextTimerID = "next_timer_id"
        case hasMore = "has_more"
    }
}

/// The world's current state at one sequence: bounded facts and timers plus the latest sequence a
/// subscriber should resume after.
public struct WorldSnapshot: Codable, Equatable, Sendable {
    public var latestSequence: Int64
    public var facts: [Fact]
    public var timers: [WorldTimer]
    public var factsTruncated: Bool
    public var timersTruncated: Bool

    public init(
        latestSequence: Int64,
        facts: [Fact],
        timers: [WorldTimer],
        factsTruncated: Bool,
        timersTruncated: Bool
    ) {
        self.latestSequence = latestSequence
        self.facts = facts
        self.timers = timers
        self.factsTruncated = factsTruncated
        self.timersTruncated = timersTruncated
    }

    private enum CodingKeys: String, CodingKey {
        case latestSequence = "latest_sequence"
        case facts
        case timers
        case factsTruncated = "facts_truncated"
        case timersTruncated = "timers_truncated"
    }
}

/// One accepted event and the facts it changed, as published on the live stream.
public struct WorldDelta: Codable, Equatable, Sendable {
    public var event: WorldEventEnvelope
    public var changedFacts: [Fact]

    public init(event: WorldEventEnvelope, changedFacts: [Fact]) {
        self.event = event
        self.changedFacts = changedFacts
    }

    private enum CodingKeys: String, CodingKey {
        case event
        case changedFacts = "changed_facts"
    }
}

/// Every frame a `/world/v1/stream` subscriber can receive.
public enum WorldStreamFrame: Equatable, Sendable {
    /// A fresh subscription's starting point; resume after `latestSequence`.
    case snapshot(WorldSnapshot)
    /// History replayed after a `Last-Event-ID` resume.
    case event(WorldEventEnvelope)
    /// A live change.
    case delta(WorldDelta)
    /// The world could not continue this subscription; reconnect and request a new snapshot.
    case resnapshotRequired
}

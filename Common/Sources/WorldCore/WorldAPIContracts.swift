import Foundation

/// Wire contracts of Creature World's `/world/v1` read API, shared by the simulator, World
/// Viewer, and the character mind. All keys are snake_case and every list is bounded.

public struct WorldHealth: Codable, Equatable, Sendable {
    public var status: String
    public var service: String
    public var buildVersion: String
    public var mongodb: String
    public var schemaVersion: Int

    public init(status: String, service: String, buildVersion: String, mongodb: String, schemaVersion: Int) {
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

import Foundation

/// The librarian's night, as the world and the Viewer read it (#229,
/// `docs/durable-learning-plan.md`): what Beaky proposed (`memory.filed`), how each item
/// stands against the record now (the review), what April checked, and what was applied
/// (`memory.filing.applied`).
public enum LibrarianFiling {
    public static let filedEventType = "memory.filed"
    public static let appliedEventType = "memory.filing.applied"
    public static let sourceKind = "librarian"

    /// The kinds the librarian never files: each has its own rules elsewhere in the world,
    /// and a rewrite would step around them. A visit ending ends what was reported about it
    /// (#228); presence and sightings are the house's; pronouns are a person's own word.
    public static let protectedPrefixes = [
        "visitor.", "presence.", WorldFacts.sightingIdentified, "house.cameras_quiet",
        WorldFacts.pronouns,
    ]

    public static func isProtected(_ predicate: String) -> Bool {
        protectedPrefixes.contains { predicate.hasPrefix($0) }
    }

    /// `librarian:beaky` for the bird whose night it was (`mind:beaky`).
    public static func source(forMind mind: SourceID) throws -> SourceID {
        let bird = mind.rawValue.split(separator: ":").last.map(String.init) ?? mind.rawValue
        return try SourceID(validating: "\(sourceKind):\(bird)")
    }
}

/// What the librarian proposed one night: the `proposal` of a `memory.filed` event.
public struct LibrarianProposal: Codable, Equatable, Sendable {
    public struct Rewrite: Codable, Equatable, Sendable {
        public var subject: EntityID
        public var predicate: String
        public var value: String
        public var replaces: [FactID]
        public var reason: String

        public init(
            subject: EntityID, predicate: String, value: String, replaces: [FactID],
            reason: String
        ) {
            self.subject = subject
            self.predicate = predicate
            self.value = value
            self.replaces = replaces
            self.reason = reason
        }
    }

    public struct Retire: Codable, Equatable, Sendable {
        public var fact: FactID
        public var reason: String

        public init(fact: FactID, reason: String) {
            self.fact = fact
            self.reason = reason
        }
    }

    public struct Same: Codable, Equatable, Sendable {
        public var ids: [EntityID]
        public var keep: EntityID
        public var sure: Bool
        public var reason: String

        public init(ids: [EntityID], keep: EntityID, sure: Bool, reason: String) {
            self.ids = ids
            self.keep = keep
            self.sure = sure
            self.reason = reason
        }

        /// The ids that go: every one but the kept.
        public var merged: [EntityID] { ids.filter { $0 != keep } }
    }

    public struct Kind: Codable, Equatable, Sendable {
        public var predicate: String
        public var meaning: String

        public init(predicate: String, meaning: String) {
            self.predicate = predicate
            self.meaning = meaning
        }
    }

    public var rewrites: [Rewrite]
    public var retires: [Retire]
    public var same: [Same]
    public var kinds: [Kind]
    public var questions: [String]
    /// What the answer proposed that the record does not hold - an id it made up, a fact
    /// twice, a change past the night's cap - and was left out.
    public var dropped: Int

    public init(
        rewrites: [Rewrite] = [], retires: [Retire] = [], same: [Same] = [],
        kinds: [Kind] = [], questions: [String] = [], dropped: Int = 0
    ) {
        self.rewrites = rewrites
        self.retires = retires
        self.same = same
        self.kinds = kinds
        self.questions = questions
        self.dropped = dropped
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rewrites = try container.decodeIfPresent([Rewrite].self, forKey: .rewrites) ?? []
        retires = try container.decodeIfPresent([Retire].self, forKey: .retires) ?? []
        same = try container.decodeIfPresent([Same].self, forKey: .same) ?? []
        kinds = try container.decodeIfPresent([Kind].self, forKey: .kinds) ?? []
        questions = try container.decodeIfPresent([String].self, forKey: .questions) ?? []
        dropped = try container.decodeIfPresent(Int.self, forKey: .dropped) ?? 0
    }

    /// As it rides in the event's payload.
    public var json: WorldJSONValue {
        get throws {
            try WorldJSON.makeDecoder().decode(
                WorldJSONValue.self, from: WorldJSON.makeEncoder().encode(self))
        }
    }

    /// The proposal of a `memory.filed` event; nil for anything else.
    public init?(filed event: WorldEventEnvelope) {
        guard event.type.rawValue == LibrarianFiling.filedEventType,
            let proposal = event.payload["proposal"],
            let data = try? WorldJSON.makeEncoder().encode(proposal),
            let decoded = try? WorldJSON.makeDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }
}

/// The four lists of a proposal, by the names they have in it.
public enum FilingList: String, Codable, CaseIterable, Comparable, Sendable {
    case rewrites
    case retires
    case same
    case kinds

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One item of a proposal: rewrite 3, same 1.
public struct FilingItemKey: Codable, Hashable, Comparable, Sendable {
    public var list: FilingList
    public var index: Int

    public init(_ list: FilingList, _ index: Int) {
        self.list = list
        self.index = index
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.list, lhs.index) < (rhs.list, rhs.index)
    }
}

/// How an item stands against the record now.
public enum FilingItemStatus: String, Codable, Sendable {
    /// It can be applied as proposed.
    case ready
    /// A fact it names is no longer current: a bird kept something newer, or April said
    /// otherwise. It is never applied; tomorrow's proposal sees the new record.
    case stale
    /// It touches what the librarian may not file: a protected kind, a kind already meant,
    /// an id already merged, a bird.
    case guarded
    /// It was applied before, from this filing.
    case applied
}

/// One item, reviewed.
public struct FilingReviewItem: Codable, Equatable, Sendable {
    public var key: FilingItemKey
    public var status: FilingItemStatus
    /// Why it is stale or guarded, in a line.
    public var reason: String?
    /// Whether it starts checked: a ready item, and of the merges only the sure.
    public var checked: Bool
    /// A rewrite of facts with an end ends at the earliest of them.
    public var validTo: Date?
    /// A merge's facts that would move to the kept id.
    public var moves: [FactID]
    /// A merge's facts that would stay, because the kept id already holds their name.
    public var stays: [FactID]

    public init(
        key: FilingItemKey, status: FilingItemStatus, reason: String? = nil, checked: Bool,
        validTo: Date? = nil, moves: [FactID] = [], stays: [FactID] = []
    ) {
        self.key = key
        self.status = status
        self.reason = reason
        self.checked = checked
        self.validTo = validTo
        self.moves = moves
        self.stays = stays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(FilingItemKey.self, forKey: .key)
        status = try container.decode(FilingItemStatus.self, forKey: .status)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        checked = try container.decode(Bool.self, forKey: .checked)
        validTo = try container.decodeIfPresent(Date.self, forKey: .validTo)
        moves = try container.decodeIfPresent([FactID].self, forKey: .moves) ?? []
        stays = try container.decodeIfPresent([FactID].self, forKey: .stays) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case key, status, reason, checked, moves, stays
        case validTo = "valid_to"
    }
}

/// A night's proposal with each item's standing: `GET /v1/filings/{eventID}/review`.
public struct FilingReview: Codable, Equatable, Sendable {
    public var filing: WorldEventEnvelope
    public var proposal: LibrarianProposal
    public var items: [FilingReviewItem]
    /// The facts the items name, as they are now, so the Viewer can show what a rewrite
    /// replaces and what a merge moves without a request per fact.
    public var facts: [Fact]

    public init(
        filing: WorldEventEnvelope, proposal: LibrarianProposal, items: [FilingReviewItem],
        facts: [Fact]
    ) {
        self.filing = filing
        self.proposal = proposal
        self.items = items
        self.facts = facts
    }

    public func item(_ key: FilingItemKey) -> FilingReviewItem? {
        items.first { $0.key == key }
    }
}

/// What April checked: `POST /v1/filings/{eventID}/apply`.
public struct FilingSelection: Codable, Equatable, Sendable {
    public var rewrites: [Int]
    public var retires: [Int]
    public var same: [Int]
    public var kinds: [Int]

    public init(rewrites: [Int] = [], retires: [Int] = [], same: [Int] = [], kinds: [Int] = []) {
        self.rewrites = rewrites
        self.retires = retires
        self.same = same
        self.kinds = kinds
    }

    public init(_ keys: some Sequence<FilingItemKey>) {
        self.init()
        for key in keys {
            switch key.list {
            case .rewrites: rewrites.append(key.index)
            case .retires: retires.append(key.index)
            case .same: same.append(key.index)
            case .kinds: kinds.append(key.index)
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rewrites = try container.decodeIfPresent([Int].self, forKey: .rewrites) ?? []
        retires = try container.decodeIfPresent([Int].self, forKey: .retires) ?? []
        same = try container.decodeIfPresent([Int].self, forKey: .same) ?? []
        kinds = try container.decodeIfPresent([Int].self, forKey: .kinds) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case rewrites, retires, same, kinds
    }

    /// Every checked item, once, in order.
    public var keys: [FilingItemKey] {
        Set(
            rewrites.map { FilingItemKey(.rewrites, $0) }
                + retires.map { FilingItemKey(.retires, $0) }
                + same.map { FilingItemKey(.same, $0) } + kinds.map { FilingItemKey(.kinds, $0) }
        ).sorted()
    }
}

/// What was applied, resolved against the record: the payload of `memory.filing.applied`.
/// It carries what the reducer needs - each replaced fact's subject and predicate, each moved
/// fact's value - so the reducer stays pure.
public struct FilingApplication: WorldEventPayload, Equatable {
    public static let eventType = try! WorldEventType(validating: LibrarianFiling.appliedEventType)

    /// A fact the application ends or moves, as it was.
    public struct Touched: Codable, Equatable, Sendable {
        public var factID: FactID
        public var subjectID: EntityID
        public var predicate: String

        public init(_ fact: Fact) {
            factID = fact.factID
            subjectID = fact.subjectID
            predicate = fact.predicate
        }

        private enum CodingKeys: String, CodingKey {
            case factID = "fact_id"
            case subjectID = "subject_id"
            case predicate
        }
    }

    public struct Rewrite: Codable, Equatable, Sendable {
        public var subjectID: EntityID
        public var predicate: String
        public var value: String
        public var validTo: Date?
        public var replaces: [Touched]

        public init(
            subjectID: EntityID, predicate: String, value: String, validTo: Date?,
            replaces: [Touched]
        ) {
            self.subjectID = subjectID
            self.predicate = predicate
            self.value = value
            self.validTo = validTo
            self.replaces = replaces
        }

        private enum CodingKeys: String, CodingKey {
            case subjectID = "subject_id"
            case predicate, value, replaces
            case validTo = "valid_to"
        }
    }

    /// A fact moving from a merged id to the kept one, with what it said.
    public struct Move: Codable, Equatable, Sendable {
        public var fact: Touched
        public var value: WorldJSONValue
        public var validTo: Date?

        public init(_ fact: Fact) {
            self.fact = Touched(fact)
            value = fact.value
            validTo = fact.validTo
        }

        private enum CodingKeys: String, CodingKey {
            case fact, value
            case validTo = "valid_to"
        }
    }

    public struct Merge: Codable, Equatable, Sendable {
        public var merged: [EntityID]
        public var keep: EntityID
        public var moves: [Move]

        public init(merged: [EntityID], keep: EntityID, moves: [Move]) {
            self.merged = merged
            self.keep = keep
            self.moves = moves
        }
    }

    /// The `memory.filed` event this applies.
    public var filing: EventID
    /// The items applied, by their place in the proposal.
    public var items: [FilingItemKey]
    public var rewrites: [Rewrite]
    public var retires: [Touched]
    public var merges: [Merge]
    public var kinds: [LibrarianProposal.Kind]

    public init(
        filing: EventID, items: [FilingItemKey], rewrites: [Rewrite] = [],
        retires: [Touched] = [], merges: [Merge] = [], kinds: [LibrarianProposal.Kind] = []
    ) {
        self.filing = filing
        self.items = items
        self.rewrites = rewrites
        self.retires = retires
        self.merges = merges
        self.kinds = kinds
    }

    /// Every id it touches, for the event's subjects.
    public var subjects: [EntityID] {
        var seen: Set<EntityID> = []
        let all =
            rewrites.flatMap { [$0.subjectID] + $0.replaces.map(\.subjectID) }
            + retires.map(\.subjectID) + merges.flatMap { $0.merged + [$0.keep] }
        return all.filter { seen.insert($0).inserted }
    }
}

/// What happened to one checked item.
public struct FilingOutcome: Codable, Equatable, Sendable {
    public var key: FilingItemKey
    public var applied: Bool
    /// Why it was skipped: its status at the moment of applying.
    public var reason: String?

    public init(key: FilingItemKey, applied: Bool, reason: String? = nil) {
        self.key = key
        self.applied = applied
        self.reason = reason
    }
}

/// The answer to an apply: each checked item's outcome, and the event, when anything was.
public struct FilingApplyResult: Codable, Equatable, Sendable {
    public var outcomes: [FilingOutcome]
    public var event: WorldEventEnvelope?

    public init(outcomes: [FilingOutcome], event: WorldEventEnvelope?) {
        self.outcomes = outcomes
        self.event = event
    }
}

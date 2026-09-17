import Foundation

/// The world's current facts about some subjects, for a percept. Bounded so a mind's prompt
/// stays a window, never a dump.
public protocol WorldKnowledgeProviding: Sendable {
    /// Facts about `subjects`, and about anyone the world knows who is named in `text` — so a
    /// question about Polly carries what the world knows of Polly.
    func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
        async throws -> [Fact]

    /// What just happened around `subjects`: the recent events for them, oldest first. Facts
    /// are the present; the happenings are the story, and the story is where a mind works out
    /// that the door unlocking and then a person at the carport was April going out.
    func recentHappenings(about subjects: [EntityID], since: Date, limit: Int)
        async throws -> [Happening]

    /// What the given predicates mean, for the glossary a mind is handed beside the facts.
    func meanings(of predicates: Set<String>) async throws -> [String: String]
}

extension WorldKnowledgeProviding {
    public func currentFacts(about subjects: [EntityID], limit: Int) async throws -> [Fact] {
        try await currentFacts(about: subjects, mentionedIn: nil, limit: limit)
    }

    public func recentHappenings(about subjects: [EntityID], since: Date, limit: Int)
        async throws -> [Happening]
    {
        []
    }

    /// Without a store, the world's own catalogue.
    public func meanings(of predicates: Set<String>) async throws -> [String: String] {
        var meanings = WorldFacts.meanings.filter { predicates.contains($0.key) }
        for predicate in predicates where meanings[predicate] == nil {
            if let family = WorldFacts.memoryFamily(of: predicate) {
                meanings[predicate] = WorldFacts.meanings[family]
            }
        }
        return meanings
    }
}

/// One thing that happened, as a mind is told it: when, what kind, to whom or where, and the
/// world's own sentence for it when it has one. Never the payload.
public struct Happening: Codable, Hashable, Sendable {
    public var occurredAt: Date
    public var type: WorldEventType
    public var subjectID: EntityID
    public var summary: String?

    public init(occurredAt: Date, type: WorldEventType, subjectID: EntityID, summary: String? = nil)
    {
        self.occurredAt = occurredAt
        self.type = type
        self.subjectID = subjectID
        self.summary = summary
    }

    /// The kinds of event worth telling a mind about. Heartbeats, timers, pieces of lines, and
    /// measurements (state, already in the facts) are not a story.
    public static func isStoryworthy(_ type: WorldEventType) -> Bool {
        let raw = type.rawValue
        if raw == "camera.watching" || raw == "environment.measurement_changed" { return false }
        return ["door.", "camera.", "motion.", "person.", "house.", "facts.", "departure."]
            .contains { raw.hasPrefix($0) }
    }

    /// Whether this event is a story, kind and source together: telemetry is not. A bird's
    /// power rail, read every thirty seconds, is a fact about its body and never a happening
    /// - thirty of them in a row pushed the door and the driveway out of the story entirely.
    public static func isStoryworthy(_ event: WorldEventEnvelope) -> Bool {
        guard isStoryworthy(event.type) else { return false }
        return !telemetrySourceKinds.contains(event.source.kind)
    }

    /// Sources whose facts are state, not story.
    public static let telemetrySourceKinds: Set<String> = ["body"]

    private enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case type
        case subjectID = "subject_id"
        case summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        type = try container.decode(WorldEventType.self, forKey: .type)
        subjectID = try EntityID(validating: container.decode(String.self, forKey: .subjectID))
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(type, forKey: .type)
        try container.encode(subjectID.rawValue, forKey: .subjectID)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

/// The world before facts: nothing is known.
public struct NoWorldKnowledge: WorldKnowledgeProviding {
    public init() {}
    public func currentFacts(about subjects: [EntityID], mentionedIn text: String?, limit: Int)
        async throws -> [Fact]
    {
        []
    }
}

public enum WorldMentions {
    /// Something the world can describe: a person, and what they are to April when the world
    /// knows; or a thing, by the words that name it ("Servo Kit ×4" for an order).
    public struct Known: Equatable, Sendable {
        public var entityID: EntityID
        public var relationship: String?
        public var words: [String]

        public init(entityID: EntityID, relationship: String? = nil, words: [String] = []) {
            self.entityID = entityID
            self.relationship = relationship
            self.words = words
        }
    }

    /// The entities among `known` whose plain name ("polly" in `person:polly`) appears as a
    /// word in `text`, case-insensitively.
    public static func mentioned(in text: String, among known: [EntityID]) -> [EntityID] {
        mentioned(in: text, among: known.map { Known(entityID: $0) })
    }

    /// By name, or by what they are to April: "my mom" finds the person whose relationship is
    /// "Mother". The words of the relationship count, and their everyday synonyms.
    public static func mentioned(in text: String, among known: [Known]) -> [EntityID] {
        let words = Set(
            text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return known.filter { person in
            let raw = person.entityID.rawValue
            guard let colon = raw.firstIndex(of: ":") else { return false }
            if words.contains(String(raw[raw.index(after: colon)...]).lowercased()) {
                return true
            }
            // A thing named by its words - exactly, or their plural: "did I order a servo?"
            // finds the Servo Kit; "the kitchen light" does not.
            let named = person.words.flatMap {
                $0.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            }
            if named.contains(where: { name in
                name.count >= 3 && !Self.stopWords.contains(name)
                    && (words.contains(name) || words.contains(name + "s")
                        || words.contains(name + "es"))
            }) {
                return true
            }
            guard let relationship = person.relationship?.lowercased() else { return false }
            let relationWords = relationship.split(whereSeparator: { !$0.isLetter }).map(
                String.init)
            return relationWords.contains { word in
                words.contains(word) || (synonyms[word] ?? []).contains { words.contains($0) }
            }
        }
        .map(\.entityID)
    }

    /// Words in an item's name that name nothing: "Kit for the Pi" is found by "kit", not "for".
    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "pack", "set", "new", "black", "white", "pcs", "piece",
        "pieces", "inch", "inches", "usb",
    ]

    /// The everyday words for a relationship: April says "mom", the card says "Mother".
    static let synonyms: [String: [String]] = [
        "mother": ["mom", "mum", "mama", "mommy"],
        "father": ["dad", "papa", "daddy"],
        "sister": ["sis"],
        "brother": ["bro"],
        "grandmother": ["grandma", "nana", "gran"],
        "grandfather": ["grandpa", "gramps"],
        "spouse": ["wife", "husband", "partner"],
        "contractor": ["builder"],
        "doctor": ["physician"],
    ]
}

public enum WorldKnowledgeLimits {
    /// The most facts a single percept carries.
    public static let maximumFacts = 40

    /// How far back the story a percept carries reaches, and how many happenings at most.
    public static let happeningsWindow: TimeInterval = 15 * 60
    public static let maximumHappenings = 30
    /// The calendar rides along: this many upcoming events at most, soonest first.
    public static let maximumUpcomingEvents = 8
    /// Words that make a question about time, widening the calendar window to a fortnight.
    /// Words that make the newest orders relevant even when nothing in them is named: "did I
    /// just order toothpaste?" when the mail called it "1 Personal Care item".
    public static let orderWords: Set<String> = [
        "order", "ordered", "ordering", "bought", "buy", "purchase", "purchased", "package",
        "packages", "parcel", "delivery", "delivered", "shipped", "shipment", "arriving",
        "arrive", "tracking",
    ]
    /// How far back an order counts as news.
    public static let recentOrderWindow: TimeInterval = 2 * 86_400

    public static let timeWords: Set<String> = [
        "weekend", "week", "tomorrow", "today", "tonight", "calendar", "schedule", "plans",
        "appointment", "appointments", "coming", "upcoming", "when", "month", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
}

/// How much a search hands back: hits are entities, each with a few of the facts that matched.
public enum WorldSearchLimits {
    public static let defaultHits = 10
    public static let maximumHits = 50
    public static let factsPerEntity = 5
}

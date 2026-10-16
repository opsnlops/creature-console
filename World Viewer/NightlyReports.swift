import Foundation
import WorldCore

/// The nightly memory, read back by night: what each bird wrote to April, and what it chose to
/// remember of the day. Built from the world's memory facts alone - a reflection is
/// `memory.reflection.<bird>.<day>`, an episode `memory.episode.<bird>.<day>.<n>` - so the
/// world needs no endpoint of its own for it. April: "Can you add something to World Viewer to
/// let me view the nightly reports by day?" (#218)
enum NightlyReports {
    /// One night some bird remembered, newest first in a list.
    struct Night: Identifiable, Hashable, Sendable {
        /// "2026-09-30", the day remembered (the run itself is the night after).
        let day: String
        /// The birds that wrote a reflection that night, by name: "beaky".
        let birds: [String]
        var id: String { day }
    }

    /// One bird's report for one night.
    struct BirdNight: Identifiable, Hashable, Sendable {
        let bird: String
        let reflection: Fact?
        let episodes: [Episode]
        var id: String { bird }

        var reflectionText: String? { reflection.flatMap { NightlyReports.text(of: $0, "text") } }
    }

    /// One thing a bird remembered: filed on every subject it is about, shown once.
    struct Episode: Identifiable, Hashable, Sendable {
        /// The predicate, which names it uniquely: "memory.episode.beaky.2026-09-30.3".
        let id: String
        let what: String
        let when: String
        let salience: Double
        let about: [EntityID]
        /// One of its facts, for the Mundane view.
        let fact: Fact
    }

    /// The nights with reflections, newest first.
    static func nights(fromReflections facts: [Fact]) -> [Night] {
        var birds: [String: Set<String>] = [:]
        for fact in facts
        where WorldFacts.memoryFamily(of: fact.predicate)
            == WorldFacts.memoryReflection && fact.value != .null
        {
            guard let bird = WorldFacts.memoryOwner(of: fact.predicate),
                let day = day(of: fact.predicate)
            else { continue }
            birds[day, default: []].insert(bird)
        }
        return birds.keys.sorted(by: >).map { Night(day: $0, birds: birds[$0]!.sorted()) }
    }

    /// One night: each bird's reflection, and its episodes most salient first. `episodes` may
    /// hold any birds' and any nights' - only this night's are taken.
    static func report(day: String, reflections: [Fact], episodes: [Fact]) -> [BirdNight] {
        var reflected: [String: Fact] = [:]
        for fact in reflections where fact.value != .null && Self.day(of: fact.predicate) == day {
            if let bird = WorldFacts.memoryOwner(of: fact.predicate) { reflected[bird] = fact }
        }
        var grouped: [String: [Fact]] = [:]
        for fact in episodes where fact.value != .null && Self.day(of: fact.predicate) == day {
            grouped[fact.predicate, default: []].append(fact)
        }
        var remembered: [String: [Episode]] = [:]
        for (predicate, facts) in grouped {
            guard let bird = WorldFacts.memoryOwner(of: predicate), let first = facts.first
            else { continue }
            remembered[bird, default: []].append(
                Episode(
                    id: predicate,
                    what: text(of: first, "what") ?? "",
                    when: text(of: first, "when") ?? "",
                    salience: number(of: first, "salience") ?? 0,
                    about: facts.map(\.subjectID).sorted { $0.rawValue < $1.rawValue },
                    fact: first))
        }
        let birds = Set(reflected.keys).union(remembered.keys).sorted()
        return birds.map { bird in
            BirdNight(
                bird: bird, reflection: reflected[bird],
                episodes: (remembered[bird] ?? []).sorted {
                    ($0.salience, $1.id) > ($1.salience, $0.id)
                })
        }
    }

    /// The day in a memory predicate: the part after the owner, "2026-09-30".
    static func day(of predicate: String) -> String? {
        let parts = predicate.split(separator: ".")
        guard parts.count >= 4, parts[0] == "memory" else { return nil }
        let day = String(parts[3])
        return day.count == 10 && day.dropFirst(4).first == "-" ? day : nil
    }

    private static func text(of fact: Fact, _ key: String) -> String? {
        if case .object(let fields) = fact.value, case .string(let text)? = fields[key] {
            return text
        }
        return nil
    }

    private static func number(of fact: Fact, _ key: String) -> Double? {
        if case .object(let fields) = fact.value, case .number(let number)? = fields[key] {
            return number
        }
        return nil
    }
}

// MARK: - The librarian's night

extension NightlyReports {
    /// What the librarian proposed for the record one night (`memory.filed`, #229): facts
    /// rewritten together, facts retired, ids that are one thing, meanings for the families
    /// it settled on, and the questions only April can answer. While she watches, nothing of
    /// it has been applied.
    struct Filing: Hashable, Sendable {
        struct Rewrite: Hashable, Sendable {
            let subject: String
            let predicate: String
            let value: String
            let replaces: Int
            let reason: String
        }
        struct Line: Hashable, Sendable {
            let what: String
            let reason: String
        }

        let day: String
        let bird: String
        let watching: Bool
        let learned: Int
        let overwritten: Int
        let rewrites: [Rewrite]
        let retires: [Line]
        let same: [Line]
        let kinds: [Line]
        let questions: [String]
        let dropped: Int
        let event: WorldEventEnvelope

        var isEmpty: Bool {
            rewrites.isEmpty && retires.isEmpty && same.isEmpty && kinds.isEmpty
                && questions.isEmpty
        }
    }

    /// One night's filing from its `memory.filed` event; nil for anything else.
    static func filing(from event: WorldEventEnvelope) -> Filing? {
        guard event.type.rawValue == "memory.filed", case .string(let day)? = event.payload["day"],
            case .object(let proposal)? = event.payload["proposal"]
        else { return nil }
        func text(_ value: WorldJSONValue?) -> String {
            if case .string(let text)? = value { return text }
            return ""
        }
        func number(_ value: WorldJSONValue?) -> Int {
            if case .number(let number)? = value { return Int(number) }
            return 0
        }
        func items(_ key: String) -> [[String: WorldJSONValue]] {
            guard case .array(let values)? = proposal[key] else { return [] }
            return values.compactMap { if case .object(let item) = $0 { item } else { nil } }
        }
        func count(_ value: WorldJSONValue?) -> Int {
            if case .array(let values)? = value { return values.count }
            return 0
        }
        return Filing(
            day: day,
            bird: event.source.id.rawValue.split(separator: ":").last.map(String.init) ?? "",
            watching: text(event.payload["mode"]) != "applied",
            learned: number(event.payload["learned"]),
            overwritten: number(event.payload["overwritten"]),
            rewrites: items("rewrites").map {
                .init(
                    subject: text($0["subject"]), predicate: text($0["predicate"]),
                    value: text($0["value"]), replaces: count($0["replaces"]),
                    reason: text($0["reason"]))
            },
            retires: items("retires").map {
                .init(what: text($0["fact"]), reason: text($0["reason"]))
            },
            same: items("same").map { item in
                var ids: [String] = []
                if case .array(let values)? = item["ids"] { ids = values.map { text($0) } }
                var sure = false
                if case .bool(true)? = item["sure"] { sure = true }
                return .init(
                    what: "\(ids.joined(separator: " = ")), keep \(text(item["keep"]))"
                        + (sure ? "" : " (not sure: a question)"),
                    reason: text(item["reason"]))
            },
            kinds: items("kinds").map {
                .init(what: text($0["predicate"]), reason: text($0["meaning"]))
            },
            questions: {
                guard case .array(let values)? = proposal["questions"] else { return [] }
                return values.map { text($0) }
            }(),
            dropped: number(proposal["dropped"]),
            event: event)
    }
}

extension Fact {
    /// Who said it, in words: "kept by Mango" for a bird, "from the address book's bridge" for
    /// the Bridge - the fact's origin (#229). Nil for a fact from before origins were kept.
    var keptBy: String? {
        guard let origin else { return nil }
        let parts = origin.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "from \(origin.rawValue)" }
        switch parts[0] {
        case "mind": return "kept by \(parts[1].capitalized)"
        case "librarian": return "filed by \(parts[1].capitalized), the librarian"
        default: return "from \(origin.rawValue)"
        }
    }
}

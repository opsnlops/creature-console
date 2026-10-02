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

import AsyncHTTPClient
import Foundation
import Logging
import Tracing
import WorldCore

/// Step 4b of the judgement plan: once a night the world says "remember the day", and the mind
/// that owns a memory model reads the day back - what happened, what was said, what it was told
/// - and writes what it will keep. Memories are human-grained on purpose: "Jesse came Sunday
/// afternoon and put the boards on the deck", never a clock time. April: "She'll know 'Jesse was
/// here on Monday' and not 'Jesse was here at 4:39:29 PM on Monday'." The exact events stay in
/// the world behind provenance. Episodes go on the people and places they are about; the
/// reflection goes on the bird. Both are kept for years: the world's retention never touches
/// them, and only their place in a prompt fades.
struct MemoryJob: Sendable {
    /// What the model gives back, as JSON.
    struct Recollection: Decodable, Equatable, Sendable {
        struct Episode: Decodable, Equatable, Sendable {
            var about: [String]
            var when: String
            var what: String
            var salience: Double
        }
        var episodes: [Episode]
        var reflection: String
    }

    /// What the model gives back for the month: the flock's beliefs, whole.
    struct Consolidation: Decodable, Equatable, Sendable {
        struct Belief: Decodable, Equatable, Sendable {
            var about: String
            var kind: String
            var what: String
            var salience: Double
            var since: String
            var from: [String]
        }
        var beliefs: [Belief]
    }

    typealias RespondJSON = @Sendable ([LocalLLMClient.Message]) async throws -> Data

    let worldURL: URL
    let characterID: EntityID
    let persona: CharacterPersona
    let houseID: EntityID
    let modelName: String
    let respondJSON: RespondJSON
    let cast: @Sendable (WorldEventEnvelope) async throws -> Void
    let client: HTTPClient
    let logger: Logger

    static let maximumEpisodes = 12
    /// Beliefs are few by design: the settled view, not a second diary.
    static let maximumBeliefs = 40
    static let maximumBeliefsPerSubject = 4
    /// How far back the consolidation reads episodes; the world hands them out for as long.
    static let beliefDays = 30
    static let reflectionDays = 7

    /// Remember `day` (`2026-09-13`, in the house's zone). `run` is the id of the
    /// `memory.consolidate` event asking: every cast is keyed by it, so a retry of the same
    /// night is idempotent while a day asked for again - by hand, or after a Forget - is new.
    func remember(day: String, run: EventID, now: Date) async throws {
        try await withSpan("agent.memory.remember") { span in
            span.attributes["agent.character_id"] = characterID.rawValue
            span.attributes["memory.day"] = day
            span.attributes["memory.run"] = run.rawValue
            let key = "memory:\(day):\(run.rawValue)"
            span.attributes["llm.model"] = modelName
            let digest = try await fetchDigest(day: day)
            span.attributes["memory.happenings"] = digest.happenings.count
            span.attributes["memory.conversation_lines"] = digest.conversation.count
            span.attributes["memory.scenes"] = digest.scenes.count
            guard
                !digest.happenings.isEmpty || !digest.conversation.isEmpty
                    || !digest.scenes.isEmpty
            else {
                logger.info("Nothing to remember", metadata: ["memory.day": "\(day)"])
                return
            }
            let transcript = Self.transcript(
                for: digest, persona: persona, characterID: characterID)
            let data = try await withSpan("llm.generate") { inner in
                inner.attributes["llm.model"] = modelName
                inner.attributes["llm.json"] = true
                return try await respondJSON(transcript)
            }
            let recollection = try JSONDecoder().decode(Recollection.self, from: data)
            let episodes = Array(recollection.episodes.prefix(Self.maximumEpisodes))
            span.attributes["memory.episodes"] = episodes.count
            // Remembering a day again replaces that day's memory: what an earlier run kept -
            // on every subject, in every slot - is taken back before the new memory is cast.
            let earlier = try await fetchMemories(of: day)
            span.attributes["memory.replaced"] = earlier.count
            for fact in earlier {
                try await self.cast(retractionEvent(fact, key: key, now: now))
            }
            var cast = 0
            let names = Self.names(in: digest, houseID: houseID, including: characterID)
            for (index, episode) in episodes.enumerated() {
                for about in episode.about.prefix(4) {
                    guard let subject = names.entity(named: about) else { continue }
                    try await self.cast(
                        episodeEvent(
                            episode, subject: subject, day: day, index: index, key: key,
                            now: now))
                    cast += 1
                }
            }
            let reflection = recollection.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reflection.isEmpty {
                try await self.cast(reflectionEvent(reflection, day: day, key: key, now: now))
            }
            // Then the month: what all those days have settled into.
            let beliefs = try await consolidate(day: day, key: key, names: names, now: now)
            span.attributes["memory.beliefs"] = beliefs
            try await self.cast(
                try WorldEventEnvelope(
                    type: WorldEventType(validating: "memory.consolidated"),
                    occurredAt: now,
                    source: source(sourceEventID: "\(key):done"),
                    subjectIDs: [characterID],
                    epistemic: EpistemicState(type: .remembered, confidence: 1),
                    payload: [
                        "day": .string(day),
                        "episodes": .number(Double(episodes.count)),
                        "facts": .number(Double(cast)),
                        "beliefs": .number(Double(beliefs)),
                        "reflection": .string(String(reflection.prefix(500))),
                        "model": .string(modelName),
                    ]))
            logger.info(
                "Remembered the day",
                metadata: [
                    "memory.day": "\(day)", "memory.episodes": "\(episodes.count)",
                    "memory.facts": "\(cast)", "memory.beliefs": "\(beliefs)",
                ])
        }
    }

    // MARK: - Beliefs

    /// Consolidation (plan Phase 9, `docs/memory-consolidation-plan.md`): the beliefs the
    /// flock holds, revised against the last month of episodes. The whole set is rewritten
    /// each night - kept, revised, dropped, added - and replaces the old one, keyed by the
    /// run like the day's episodes. Returns how many beliefs were cast.
    func consolidate(day: String, key: String, names: EntityNames, now: Date) async throws -> Int {
        try await withSpan("agent.memory.consolidate") { span in
            let cutoff = Self.dayString(daysBefore: Self.beliefDays, of: day)
            let episodes = try await fetchFacts(prefix: WorldFacts.memoryEpisode + ".")
                .filter { Self.day(of: $0.predicate).map { $0 >= cutoff } ?? false }
            let held = try await fetchFacts(prefix: WorldFacts.memoryBelief + ".")
            let reflections = try await fetchFacts(prefix: WorldFacts.memoryReflection + ".")
                .filter {
                    $0.subjectID == characterID
                        && (Self.day(of: $0.predicate).map {
                            $0 >= Self.dayString(daysBefore: Self.reflectionDays, of: day)
                        } ?? false)
                }
            span.attributes["memory.episodes_read"] = episodes.count
            span.attributes["memory.beliefs_held"] = held.count
            guard !episodes.isEmpty else { return 0 }
            let transcript = Self.beliefTranscript(
                held: held, episodes: episodes, reflections: reflections, persona: persona,
                characterID: characterID)
            let data = try await withSpan("llm.generate") { inner in
                inner.attributes["llm.model"] = modelName
                inner.attributes["llm.json"] = true
                return try await respondJSON(transcript)
            }
            let consolidation = try JSONDecoder().decode(Consolidation.self, from: data)
            // The day's names, plus everyone with an episode or a belief; nobody new.
            var names = names
            names.add((episodes + held).map(\.subjectID))
            // Resolved and grouped, so each subject's beliefs take numbered slots in turn.
            var grouped: [EntityID: [Consolidation.Belief]] = [:]
            var order: [EntityID] = []
            for belief in consolidation.beliefs.prefix(Self.maximumBeliefs)
            where WorldFacts.beliefKinds.contains(belief.kind) {
                guard let subject = names.knownEntity(named: belief.about) else { continue }
                if grouped[subject] == nil { order.append(subject) }
                grouped[subject, default: []].append(belief)
            }
            for fact in held {
                try await self.cast(retractionEvent(fact, key: key, stage: "unbelieve", now: now))
            }
            var cast = 0
            for subject in order {
                let kept = grouped[subject]!.sorted { $0.salience > $1.salience }
                    .prefix(Self.maximumBeliefsPerSubject)
                for (index, belief) in kept.enumerated() {
                    try await self.cast(
                        beliefEvent(belief, subject: subject, index: index, key: key, now: now))
                    cast += 1
                }
            }
            span.attributes["memory.beliefs"] = cast
            return cast
        }
    }

    static func beliefTranscript(
        held: [Fact], episodes: [Fact], reflections: [Fact], persona: CharacterPersona,
        characterID: EntityID
    ) -> [LocalLLMClient.Message] {
        let name = FactPhrasing.name(of: characterID)
        let system =
            persona.rendered(present: []) + """


                It is the middle of the night. Below is what you, \(name), have come to believe so \
                far, and your memories of the last month - episodes about the people, places, and \
                things around you, and your own reflections. Write what you believe now. Answer with \
                one JSON object and nothing else: {"beliefs": [{"about": "April", "kind": "habit", \
                "what": "April gets excited about new robot parts and wants to hear the moment a \
                package is on the porch", "salience": 0.8, "since": "September 2026", "from": \
                ["2026-09-13", "2026-09-15"]}]}.

                Rules. A belief is something settled, not something that happened: a habit or \
                preference of theirs; what someone is to you ("Jesse is April's contractor; he \
                texts when he is on his way"); or, on a bird - yourself included - what it tends \
                to do and whether it has worn thin ("Mango's database joke has been made three \
                times; it is worn out"). "kind" is habit, preference, relationship, or self. \
                "about" names the person, place, thing, or bird as the record does. "from" lists \
                the days it rests on. Keep a belief that still holds (copy it, adding new days), \
                revise one the month has changed, drop one the record contradicts, and add one when \
                more than one day shows it - or one day when April said it outright. At most \
                \(maximumBeliefsPerSubject) per subject; leave out the trivial. "salience" is how \
                much it should shape what you say, 0 to 1. Only what the record shows; never \
                invent. No emoji.
                """
        var body = "What you believe now:\n"
        if held.isEmpty {
            body += "- nothing settled yet\n"
        }
        for fact in held {
            body +=
                "- \(FactPhrasing.subjectName(of: fact.subjectID)): \(FactPhrasing.rendered(fact.value))\n"
        }
        body += "\nYour memories of the last month, oldest first:\n"
        for fact in episodes.sorted(by: { $0.predicate < $1.predicate }) {
            body +=
                "- \(FactPhrasing.subjectName(of: fact.subjectID)): \(FactPhrasing.rendered(fact.value))\n"
        }
        if !reflections.isEmpty {
            body += "\nYour reflections:\n"
            for fact in reflections.sorted(by: { $0.predicate < $1.predicate }) {
                body += "- \(FactPhrasing.rendered(fact.value))\n"
            }
        }
        return [
            LocalLLMClient.Message(role: .system, content: system),
            LocalLLMClient.Message(role: .user, content: body),
        ]
    }

    /// The day a memory predicate carries: `memory.episode.2026-09-13.2` → `2026-09-13`.
    static func day(of predicate: String) -> String? {
        guard let family = WorldFacts.memoryFamily(of: predicate) else { return nil }
        let rest = predicate.dropFirst(family.count + 1)
        let day = rest.split(separator: ".").first.map(String.init) ?? ""
        return day.count == 10 ? day : nil
    }

    /// `days` before `day`, as a day string; ISO days compare as strings.
    static func dayString(daysBefore days: Int, of day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard parts.count == 3,
            let date = calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
            let earlier = calendar.date(byAdding: .day, value: -days, to: date)
        else { return day }
        let p = calendar.dateComponents([.year, .month, .day], from: earlier)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    private func beliefEvent(
        _ belief: Consolidation.Belief, subject: EntityID, index: Int, key: String, now: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"),
            occurredAt: now,
            source: source(sourceEventID: "\(key):belief:\(subject.rawValue):\(index + 1)"),
            subjectIDs: [subject],
            epistemic: EpistemicState(
                type: .remembered, confidence: min(1, max(0, belief.salience))),
            payload: [
                "subject_id": .string(subject.rawValue),
                "predicate": .string("\(WorldFacts.memoryBelief).\(index + 1)"),
                "value": .object([
                    "kind": .string(belief.kind),
                    "what": .string(String(belief.what.prefix(400))),
                    "salience": .number(min(1, max(0, belief.salience))),
                    "since": .string(String(belief.since.prefix(40))),
                    "from": .array(belief.from.prefix(12).map { .string(String($0.prefix(10))) }),
                ]),
            ])
    }

    // MARK: - The prompt

    static func transcript(for digest: DayDigest, persona: CharacterPersona, characterID: EntityID)
        -> [LocalLLMClient.Message]
    {
        let name = FactPhrasing.name(of: characterID)
        let system =
            persona.rendered(present: []) + """


                It is the middle of the night and the day is over. Below is the world's record of \
                \(digest.day): what the house saw, what was said in the room and on April's phone, \
                and what April told you. Write what you, \(name), will remember of it. Answer with one \
                JSON object and nothing else: {"episodes": [{"about": ["Jesse", "the front door"], \
                "when": "Sunday afternoon", "what": "Jesse came by and put the boards on the deck; \
                April was pleased", "salience": 0.7}], "reflection": "…"}.

                Rules. An episode is one thing that happened, in a sentence or two, about the people, \
                places, or the house it concerns ("about" names them as they appear in the record: a \
                person's first name, "the front door", "the house", a bird's name, or for a named \
                thing such as a car or a printer, "thing: Hopper"). "when" is \
                human-grained - "Sunday afternoon", "late Sunday night", "around dinner" - never a \
                clock time. "salience" is how much it will matter later, 0 to 1: a contractor \
                finishing the deck is 0.8, April going to the store is 0.2, a bird at the feeder is 0. \
                Leave out anything that will not matter tomorrow; a quiet day may have no episodes. \
                The reflection is one short paragraph in your own voice about what you came to know \
                today - about April, the house, the other birds, yourself - or an empty string. Only \
                what the record shows; never invent. No emoji.
                """
        var body = "The record of \(digest.day) (\(digest.timeZone)).\n\n"
        if !digest.happenings.isEmpty {
            body += "What the house saw, in order:\n"
            for h in digest.happenings {
                body +=
                    "- \(clock(h.occurredAt, digest)): \(h.summary ?? "\(h.type.rawValue) at \(FactPhrasing.placeName(of: h.subjectID).lowercased())")\n"
            }
            body += "\n"
        }
        if !digest.conversation.isEmpty {
            body += "What was said between April and the birds:\n"
            for line in digest.conversation {
                body +=
                    "- \(clock(line.at, digest)) \(FactPhrasing.name(of: EntityID(rawValue: line.who) ?? characterID)): \(line.text)\n"
            }
            body += "\n"
        }
        if !digest.scenes.isEmpty {
            body += "Scenes in the room:\n"
            for scene in digest.scenes {
                body += "- \(clock(scene.openedAt, digest)) (\(scene.trigger))\n"
                for line in scene.lines {
                    body +=
                        "    \(FactPhrasing.name(of: EntityID(rawValue: line.who) ?? characterID)): \(line.text)\n"
                }
            }
            body += "\n"
        }
        if !digest.learned.isEmpty {
            body += "What the world was told:\n"
            for line in digest.learned {
                body += "- \(clock(line.at, digest)) by \(line.who): \(line.text)\n"
            }
        }
        return [
            LocalLLMClient.Message(role: .system, content: system),
            LocalLLMClient.Message(role: .user, content: body),
        ]
    }

    private static func clock(_ date: Date, _ digest: DayDigest) -> String {
        FactPhrasing.clock(date, in: TimeZone(identifier: digest.timeZone) ?? .current)
    }

    // MARK: - Casting

    private func episodeEvent(
        _ episode: Recollection.Episode, subject: EntityID, day: String, index: Int, key: String,
        now: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"),
            occurredAt: now,
            source: source(sourceEventID: "\(key):episode:\(index):\(subject.rawValue)"),
            subjectIDs: [subject],
            epistemic: EpistemicState(
                type: .remembered, confidence: min(1, max(0, episode.salience))),
            payload: [
                "subject_id": .string(subject.rawValue),
                // A fact is one value per subject and predicate, so the predicate carries the
                // day and the episode's place in it: every day's memory of a subject stands
                // beside the last, and a day's episodes beside each other. Remembering a day
                // again fills the same places.
                "predicate": .string("\(WorldFacts.memoryEpisode).\(day).\(index + 1)"),
                "value": .object([
                    "day": .string(day),
                    "when": .string(String(episode.when.prefix(80))),
                    "what": .string(String(episode.what.prefix(400))),
                    "salience": .number(min(1, max(0, episode.salience))),
                ]),
            ])
    }

    /// Nothing in the fact's place, valid for a moment: the same retraction as the Viewer's
    /// Forget, from the mind that kept it.
    private func retractionEvent(_ fact: Fact, key: String, stage: String = "replace", now: Date)
        throws -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"),
            occurredAt: now,
            source: source(sourceEventID: "\(key):\(stage):\(fact.factID.rawValue)"),
            subjectIDs: [fact.subjectID],
            epistemic: EpistemicState(type: .remembered, confidence: 1),
            payload: [
                "subject_id": .string(fact.subjectID.rawValue),
                "predicate": .string(fact.predicate),
                "value": .null,
                "valid_for_seconds": .number(1),
            ])
    }

    private func reflectionEvent(_ text: String, day: String, key: String, now: Date) throws
        -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"),
            occurredAt: now,
            source: source(sourceEventID: "\(key):reflection"),
            subjectIDs: [characterID],
            epistemic: EpistemicState(type: .remembered, confidence: 1),
            payload: [
                "subject_id": .string(characterID.rawValue),
                "predicate": .string("\(WorldFacts.memoryReflection).\(day)"),
                "value": .object([
                    "day": .string(day), "text": .string(String(text.prefix(1_000))),
                ]),
            ])
    }

    private func source(sourceEventID: String) -> EventSource {
        EventSource(
            id: (try? SourceID(
                validating: "mind:\(FactPhrasing.name(of: characterID).lowercased())"))
                ?? SourceID(rawValue: "mind:memory")!,
            kind: "mind", sourceEventID: sourceEventID)
    }

    /// The names in the day's record: the birds are everyone who spoke as a `character:`, plus
    /// the one remembering, so "Mango" in an episode finds `character:mango`.
    static func names(in digest: DayDigest, houseID: EntityID, including own: EntityID)
        -> EntityNames
    {
        let spoke = digest.conversation.map(\.who) + digest.scenes.flatMap { $0.lines.map(\.who) }
        var names = EntityNames(houseID: houseID, characters: [own])
        names.add(spoke.compactMap { EntityID(rawValue: $0) })
        // Everything the day's record touched is known: a memory about the Information
        // Bridge lands on thing:information-bridge, not on a person of that name.
        names.add(digest.happenings.map(\.subjectID))
        names.add(digest.learned.compactMap { EntityID(rawValue: $0.who) })
        return names
    }

    // MARK: - The digest

    private func fetchDigest(day: String) async throws -> DayDigest {
        var url = worldURL
        url.append(path: "days")
        url.append(path: day)
        let request = HTTPClientRequest(url: url.absoluteString)
        let response = try await client.execute(request, timeout: .seconds(30), logger: logger)
        let body = try await response.body.collect(upTo: 8 * 1_048_576)
        guard response.status == .ok else {
            throw WorldResponderError.unavailable(status: UInt(response.status.code))
        }
        return try WorldJSON.makeDecoder().decode(
            DayDigest.self, from: Data(body.readableBytesView))
    }

    /// Every memory of `day` the world currently holds, on every subject: the episodes
    /// (`memory.episode.<day>.`) and the reflection (`memory.reflection.<day>`).
    private func fetchMemories(of day: String) async throws -> [Fact] {
        try await fetchFacts(prefix: "\(WorldFacts.memoryEpisode).\(day).")
            + fetchFacts(prefix: "\(WorldFacts.memoryReflection).\(day)")
    }

    /// Every current fact whose predicate starts with `prefix`, on every subject, paged.
    private func fetchFacts(prefix: String) async throws -> [Fact] {
        var memories: [Fact] = []
        do {
            var after: FactID?
            repeat {
                var url = worldURL
                url.append(path: "facts")
                url.append(
                    queryItems: [
                        URLQueryItem(name: "predicate_prefix", value: prefix),
                        URLQueryItem(name: "limit", value: "200"),
                    ]
                        + (after.map { [URLQueryItem(name: "after_fact_id", value: $0.rawValue)] }
                            ?? []))
                let request = HTTPClientRequest(url: url.absoluteString)
                let response = try await client.execute(
                    request, timeout: .seconds(30), logger: logger)
                let body = try await response.body.collect(upTo: 8 * 1_048_576)
                guard response.status == .ok else {
                    throw WorldResponderError.unavailable(status: UInt(response.status.code))
                }
                let page = try WorldJSON.makeDecoder().decode(
                    WorldFactPage.self, from: Data(body.readableBytesView))
                memories += page.facts
                after = page.hasMore ? page.nextFactID : nil
            } while after != nil
        }
        return memories
    }
}

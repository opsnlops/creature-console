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

    /// Remember `day` (`2026-09-13`, in the house's zone).
    func remember(day: String, now: Date) async throws {
        try await withSpan("agent.memory.remember") { span in
            span.attributes["agent.character_id"] = characterID.rawValue
            span.attributes["memory.day"] = day
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
            var cast = 0
            for (index, episode) in episodes.enumerated() {
                for about in episode.about.prefix(4) {
                    guard
                        let subject = LearnedFact.entity(named: about, houseID: houseID)
                            ?? Self.character(named: about)
                    else { continue }
                    try await self.cast(
                        episodeEvent(
                            episode, subject: subject, day: day, index: index, now: now))
                    cast += 1
                }
            }
            let reflection = recollection.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reflection.isEmpty {
                try await self.cast(reflectionEvent(reflection, day: day, now: now))
            }
            try await self.cast(
                try WorldEventEnvelope(
                    type: WorldEventType(validating: "memory.consolidated"),
                    occurredAt: now,
                    source: source(sourceEventID: "memory:\(day):done"),
                    subjectIDs: [characterID],
                    epistemic: EpistemicState(type: .remembered, confidence: 1),
                    payload: [
                        "day": .string(day),
                        "episodes": .number(Double(episodes.count)),
                        "facts": .number(Double(cast)),
                        "reflection": .string(String(reflection.prefix(500))),
                        "model": .string(modelName),
                    ]))
            logger.info(
                "Remembered the day",
                metadata: [
                    "memory.day": "\(day)", "memory.episodes": "\(episodes.count)",
                    "memory.facts": "\(cast)",
                ])
        }
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
                person's first name, "the front door", "the house", or a bird's name). "when" is \
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
        _ episode: Recollection.Episode, subject: EntityID, day: String, index: Int, now: Date
    ) throws -> WorldEventEnvelope {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"),
            occurredAt: now,
            source: source(sourceEventID: "memory:\(day):episode:\(index):\(subject.rawValue)"),
            subjectIDs: [subject],
            epistemic: EpistemicState(
                type: .remembered, confidence: min(1, max(0, episode.salience))),
            payload: [
                "subject_id": .string(subject.rawValue),
                // One predicate per day, so every day's memory of a subject stands beside the
                // last instead of replacing it.
                "predicate": .string("\(WorldFacts.memoryEpisode).\(day)"),
                "value": .object([
                    "day": .string(day),
                    "when": .string(String(episode.when.prefix(80))),
                    "what": .string(String(episode.what.prefix(400))),
                    "salience": .number(min(1, max(0, episode.salience))),
                ]),
            ])
    }

    private func reflectionEvent(_ text: String, day: String, now: Date) throws
        -> WorldEventEnvelope
    {
        try WorldEventEnvelope(
            type: WorldEventType(validating: "facts.given"),
            occurredAt: now,
            source: source(sourceEventID: "memory:\(day):reflection"),
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

    static func character(named name: String) -> EntityID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["beaky", "mango", "kenny", "caroll", "cobalt", "crow"].contains(trimmed) else {
            return nil
        }
        return EntityID(rawValue: "character:\(trimmed)")
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
}

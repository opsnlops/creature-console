import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import Tracing
import WorldCore

/// Beaky's night job beside remembering: filing what the minds kept (#229,
/// `docs/durable-learning-plan.md`). The flock's learned facts are shared, so one bird files
/// them for all - the lead, while the others (and April) sleep.
///
/// On 2026-10-14 April told the birds about her flight training, and the record split one
/// topic between September's `flight.*` and the night's `person.flight_*`; Mango's keeping
/// replaced Beaky's five minutes after she kept it. The librarian reads every fact a mind kept
/// and what it filed before - never what it may not file (#253) - what a later keeping
/// replaced, and what the world's kinds mean, and proposes: facts
/// rewritten together under one name, stale ones retired, ids that are one thing, a meaning for
/// each family it settles on, and the questions only April can answer.
///
/// This first slice only *watches*: the proposal is recorded as a `memory.filed` event, for the
/// Viewer and for April to read, and nothing is changed. Applying it comes once a night or two
/// of proposals have been read.
struct Librarian: Sendable {
    let worldURL: URL
    let characterID: EntityID
    let persona: CharacterPersona
    let model: MemoryModel
    let cast: @Sendable (WorldEventEnvelope) async throws -> Void
    let client: HTTPClient
    let logger: Logger
    var capture: GenAIContentCapture = .off

    /// The most changes one night may propose; the rest wait for the next.
    static let maximumChanges = 40
    /// How far back a replaced keeping is looked for: the day just remembered, and a margin.
    static let overwrittenWindow: TimeInterval = 26 * 3_600

    var name: String {
        persona.name ?? FactPhrasing.name(of: characterID)
    }

    // MARK: - The night

    /// File the record after remembering `day`. `run` is the `memory.consolidate` event that
    /// asked; the proposal is keyed by it, so a retry of the same night records once.
    func file(day: String, run: EventID, now: Date) async throws {
        try await withSpan("agent.librarian.file") { span in
            span.attributes["agent.character_id"] = characterID.rawValue
            span.attributes["memory.day"] = day
            span.attributes["memory.run"] = run.rawValue
            let (learned, merged) = Self.shelf(try await fetchKept())
            span.attributes["librarian.learned"] = learned.count
            guard !learned.isEmpty else {
                logger.info("Nothing kept to file", metadata: ["memory.day": "\(day)"])
                return
            }
            let overwritten = Self.shelf(
                try await fetchOverwritten(since: now.addingTimeInterval(-Self.overwrittenWindow)),
                merged: merged)
            span.attributes["librarian.overwritten"] = overwritten.count
            let kindPage = try await fetchKinds()
            let kinds = Self.kinds(for: learned, from: kindPage)
            let candidates = try await fetchKindCandidates()
            span.attributes["librarian.kind_candidates"] = candidates.count
            let transcript = Self.transcript(
                learned: learned, overwritten: overwritten, kinds: kinds,
                candidates: candidates, name: name)
            let data = try await GenAI.invokeAgent(
                name, conversationID: "librarian:\(day):\(run.rawValue)", kind: .memory,
                capture: capture, model: model.modelName, outputType: "json"
            ) { _ in
                try await ask(transcript, customID: "librarian:\(day):\(run.rawValue)")
            }
            let proposal = Self.proposal(
                from: data, learned: learned, overwritten: overwritten, candidates: candidates,
                meant: Set(kindPage.kinds.map(\.predicate)))
            span.attributes["librarian.rewrites"] = proposal.rewrites.count
            span.attributes["librarian.renames"] = proposal.renames.count
            span.attributes["librarian.retires"] = proposal.retires.count
            span.attributes["librarian.same"] = proposal.same.count
            span.attributes["librarian.questions"] = proposal.questions.count
            span.attributes["librarian.dropped"] = proposal.dropped
            try await cast(
                try WorldEventEnvelope(
                    type: WorldEventType(validating: LibrarianFiling.filedEventType),
                    occurredAt: now,
                    source: EventSource(
                        id: try SourceID(validating: "mind:\(name.lowercased())"), kind: "mind",
                        sourceEventID: "librarian:\(day):\(run.rawValue)"),
                    subjectIDs: [characterID],
                    epistemic: EpistemicState(type: .remembered, confidence: 1),
                    payload: [
                        "day": .string(day),
                        "mode": .string("watching"),
                        "model": .string(model.modelName),
                        "learned": .number(Double(learned.count)),
                        "overwritten": .number(Double(overwritten.count)),
                        "proposal": try proposal.json,
                    ]))
            logger.info(
                "Filed the record (watching)",
                metadata: [
                    "memory.day": "\(day)", "librarian.rewrites": "\(proposal.rewrites.count)",
                    "librarian.retires": "\(proposal.retires.count)",
                    "librarian.same": "\(proposal.same.count)",
                    "librarian.questions": "\(proposal.questions.count)",
                    "librarian.dropped": "\(proposal.dropped)",
                ])
        }
    }

    /// One question, through the provider's batch when there is one - half the price, and
    /// nobody is waiting at night - asked now when the batch will not answer.
    private func ask(_ transcript: [LocalLLMClient.Message], customID: String) async throws
        -> Data
    {
        guard let batch = model.batch else { return try await model.ask(transcript) }
        do {
            let batchID = try await batch.submit(transcript, customID)
            return try await batch.answer(batchID, customID)
        } catch {
            logger.warning(
                "The librarian's batch did not answer; asking now",
                metadata: ["error": "\(error)"])
            return try await model.ask(transcript)
        }
    }

    // MARK: - What can be filed

    /// The record the night files (#253): what the minds kept and what the librarian filed
    /// before, held to what the World's review can take. On 2026-10-19 April could apply 4 of
    /// the night's 19 items: 9 touched kinds with their own rules, and 3 merged ids merged
    /// already - `person:jessie` keeps its `visitor.*` facts, which no merge moves, so the record
    /// showed two ids every night. Neither is shown now, nor whatever stayed on a merged id.
    static func shelf(_ kept: [Fact]) -> (learned: [Fact], merged: Set<EntityID>) {
        let merged = Set(kept.compactMap(mergedAway))
        return (kept.filter { mayFile($0) && !merged.contains($0.subjectID) }, merged)
    }

    /// What was written over, held the same way: the old value and the new.
    static func shelf(_ overwritten: [OverwrittenFact], merged: Set<EntityID>)
        -> [OverwrittenFact]
    {
        overwritten.filter { item in
            [item.replaced, item.by].allSatisfy { mayFile($0) && !merged.contains($0.subjectID) }
        }
    }

    /// Whether a fact's kind is the librarian's to file: never one with its own rules
    /// (visitors, presence, sightings, the cameras' quiet, pronouns), never the world's own
    /// bookkeeping - not even an `entity.same_as` a bird kept herself.
    static func mayFile(_ fact: Fact) -> Bool { mayFile(fact.predicate) }

    static func mayFile(_ predicate: String) -> Bool {
        !LibrarianFiling.isProtected(predicate)
            && !WorldKnowledgeLimits.worldOnlyPredicates.contains(predicate)
    }

    /// The id an `entity.same_as` merged away, as the World's review reads it: onto another
    /// id. A value that is no id ("person: Robin") merges nothing.
    static func mergedAway(_ fact: Fact) -> EntityID? {
        guard fact.predicate == WorldFacts.entitySameAs, case .string(let raw) = fact.value,
            let into = EntityID(rawValue: raw), into != fact.subjectID
        else { return nil }
        return fact.subjectID
    }

    /// Whose current facts the record holds: what the birds kept, and what the librarian filed.
    static let origins = ["mind:", "\(LibrarianFiling.sourceKind):"]

    // MARK: - The prompt

    /// The kinds whose family the learned facts use - `flight.*` when `flight.hope` is kept -
    /// so the librarian files into the names already meant, not every sensor's.
    static func kinds(for learned: [Fact], from page: FactKindPage) -> [FactKind] {
        let families = Set(learned.map(family(of:)))
        return page.kinds.filter { families.contains(family(of: $0.predicate)) }
            .sorted { $0.predicate < $1.predicate }
    }

    static func family(of fact: Fact) -> String { family(of: fact.predicate) }

    static func family(of predicate: String) -> String {
        predicate.split(separator: ".").first.map(String.init) ?? predicate
    }

    static func transcript(
        learned: [Fact], overwritten: [OverwrittenFact], kinds: [FactKind],
        candidates: [KindCandidate] = [], name: String
    ) -> [LocalLLMClient.Message] {
        [
            .init(role: .system, content: instructions(name: name)),
            .init(
                role: .user,
                content: record(
                    learned: learned, overwritten: overwritten, kinds: kinds,
                    candidates: candidates)),
        ]
    }

    /// The kinds a rename may give: what a misfiled person really is (#236).
    static let renameKinds: Set<String> = ["place", "thing", "spell"]

    static func instructions(name: String) -> String {
        """
        You are \(name), and tonight, while the other birds and April sleep, you are the \
        flock's librarian. The birds keep what April tells them as facts: a subject (who or \
        what it is about), a predicate (the name it is filed under, a short dotted word like \
        flight.training), and a value. Each name holds one value, and keeping it again \
        replaces the old one. Kept in the moment, the record scatters: one topic under \
        several names, near-duplicates, things that were true for a week, a value one bird \
        kept that another wrote over, one place under several ids.

        File it. Propose, as one JSON object:
        {"rewrites": [{"subject": "<an id from the record>", "predicate": "<family.name>", \
        "value": "<the whole of it, in plain words>", "replaces": ["<fact id>", ...], \
        "reason": "<one line>"}],
        "retires": [{"fact": "<fact id>", "reason": "<one line>"}],
        "same": [{"ids": ["<id>", "<id>"], "keep": "<one of them>", "sure": true or false, \
        "reason": "<one line>"}],
        "renames": [{"id": "<an id from \"may be the wrong kind\">", "to": "<the same name, \
        the right kind: place:, thing:, or spell:>", "reason": "<one line>"}],
        "kinds": [{"predicate": "<family.name>", "meaning": "<what a value under it says, \
        one sentence>"}],
        "questions": ["<a plain question only April can answer>"]}

        - A rewrite folds facts about one topic on one subject into one, under a name that \
        fits beside the others: name the family by the topic, flight.landings, never \
        person.flight_landings. Use a family already meant (listed under "what kinds mean") \
        when one fits. It replaces every fact it lists, and its value holds everything they \
        said - never less, never anything they did not say. A replaced value under \
        "written over" may be folded back in.
        - Retire what is no longer so: news that is old now, a plan whose day is past, \
        something a newer fact contradicts. Never retire something only because it is old. \
        A delivery a bird kept - a package delivered, on its way, or expected - is news only \
        for a few days: once it arrived, or was due, more than three days ago, retire it. \
        The mail's own orders (order:...) the world settles by itself; leave those.
        - Same is for ids that are one thing: one place, one person, one plan. Sure only when \
        the record itself says so - the same name, the same description. Never sure about a \
        person from a role alone: two people can both clean a house. When not sure, it is \
        a question.
        - A rename is for an id filed as the wrong kind: a restaurant, a church, a town, or a \
        ferry filed as a person - person:rocket-taco is place:rocket-taco. Rename only from \
        the ids listed as maybe the wrong kind, and only when what is said of it shows it is \
        not a person; a person with an unusual name stays a person.
        - A kind gives each new name you settle on its meaning, for every bird to read. A name \
        listed under "what kinds mean" keeps the meaning it has.
        - Leave alone what is already filed well. Use only the fact ids and subject ids in \
        the record. At most \(maximumChanges) rewrites, retires, sames, and renames together. If \
        nothing needs filing, answer with empty lists.
        Answer with the JSON object only.
        """
    }

    /// The record as the librarian reads it: the kept and filed facts by subject, what was
    /// written over, and the kinds already meant.
    static func record(
        learned: [Fact], overwritten: [OverwrittenFact], kinds: [FactKind],
        candidates: [KindCandidate] = []
    ) -> String {
        var lines = ["What the minds kept, and what you filed before, by subject:"]
        let bySubject = Dictionary(grouping: learned, by: \.subjectID)
        for subject in bySubject.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            lines.append("")
            lines.append(subject.rawValue)
            for fact in bySubject[subject]!.sorted(by: { $0.predicate < $1.predicate }) {
                let keeper = isFiled(fact) ? "filed by you" : "kept by \(who(fact))"
                lines.append(
                    "  [\(fact.factID.rawValue)] \(fact.predicate) = \(text(of: fact.value))"
                        + " (\(keeper), \(day(fact.validFrom)))")
            }
        }
        if !overwritten.isEmpty {
            lines.append("")
            lines.append("Written over since yesterday (the old value is no longer kept):")
            for item in overwritten {
                lines.append(
                    "  \(item.replaced.subjectID.rawValue) \(item.replaced.predicate): "
                        + "\"\(text(of: item.replaced.value))\" (\(who(item.replaced))) "
                        + "was replaced by [\(item.by.factID.rawValue)] \"\(text(of: item.by.value))\" "
                        + "(\(who(item.by)))")
            }
        }
        if !candidates.isEmpty {
            lines.append("")
            lines.append(
                "May be the wrong kind (filed as a person, but nobody named it one - no address "
                    + "book card, nothing a bird kept says it is a person):")
            for candidate in candidates {
                lines.append("  \(candidate.id.rawValue)")
                for said in candidate.said { lines.append("    - \(said)") }
            }
        }
        if !kinds.isEmpty {
            lines.append("")
            lines.append("What kinds mean:")
            for kind in kinds { lines.append("  \(kind.predicate): \(kind.meaning)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Filed by the librarian: its own earlier work, which it may fold a new keeping into.
    private static func isFiled(_ fact: Fact) -> Bool {
        fact.origin?.rawValue.hasPrefix("\(LibrarianFiling.sourceKind):") == true
    }

    private static func who(_ fact: Fact) -> String {
        isFiled(fact) ? "you" : fact.origin?.rawValue ?? "a mind"
    }

    private static func text(of value: WorldJSONValue) -> String {
        if case .string(let text) = value { return text }
        guard let data = try? WorldJSON.makeEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - The answer

    /// One night's proposal - the shape the world reviews and applies (`LibrarianProposal`).
    typealias Proposal = LibrarianProposal

    /// The model's answer, held to the record: only facts and subjects it was shown, each
    /// fact touched once, predicates of the dotted shape, at most `maximumChanges` changes.
    /// What does not hold is counted and left out, never guessed at. And held to what the
    /// World's review can take (#253): never a kind the librarian may not file, never a name
    /// the record holds with a fact the rewrite does not fold in, never a meaning for a kind
    /// in `meant` - each of those the review would guard, and April could not apply.
    static func proposal(
        from data: Data, learned: [Fact], overwritten: [OverwrittenFact],
        candidates: [KindCandidate] = [], meant: Set<String> = []
    )
        -> Proposal
    {
        var proposal = Proposal()
        guard
            let answer = try? WorldJSON.makeDecoder().decode(WorldJSONValue.self, from: data),
            case .object(let fields) = answer
        else {
            proposal.dropped = 1
            return proposal
        }
        let known = Set(learned.map(\.factID) + overwritten.map(\.by.factID))
        let subjects = Set(learned.map(\.subjectID))
        var touched: Set<FactID> = []
        var changes = 0
        func string(_ value: WorldJSONValue?) -> String? {
            if case .string(let text)? = value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
        func items(_ key: String) -> [[String: WorldJSONValue]] {
            guard case .array(let values)? = fields[key] else { return [] }
            return values.compactMap { if case .object(let item) = $0 { item } else { nil } }
        }
        for item in items("rewrites") {
            guard changes < maximumChanges,
                let subject = string(item["subject"]).flatMap(EntityID.init(rawValue:)),
                subjects.contains(subject),
                let predicate = string(item["predicate"]), LearnedFact.isPredicate(predicate),
                !predicate.hasPrefix("memory."), mayFile(predicate),
                let value = string(item["value"]),
                case .array(let raw)? = item["replaces"]
            else {
                proposal.dropped += 1
                continue
            }
            let replaces = raw.compactMap { string($0).flatMap(FactID.init(rawValue:)) }
            // A name holds one value: writing it ends what is there, so that must be folded in.
            let held = learned.contains {
                $0.subjectID == subject && $0.predicate == predicate
                    && !replaces.contains($0.factID)
            }
            guard !replaces.isEmpty, replaces.count == raw.count, !held,
                replaces.allSatisfy({ known.contains($0) && !touched.contains($0) })
            else {
                proposal.dropped += 1
                continue
            }
            touched.formUnion(replaces)
            changes += 1
            proposal.rewrites.append(
                .init(
                    subject: subject, predicate: predicate, value: value, replaces: replaces,
                    reason: string(item["reason"]) ?? ""))
        }
        for item in items("retires") {
            guard changes < maximumChanges,
                let fact = string(item["fact"]).flatMap(FactID.init(rawValue:)),
                known.contains(fact), !touched.contains(fact)
            else {
                proposal.dropped += 1
                continue
            }
            touched.insert(fact)
            changes += 1
            proposal.retires.append(.init(fact: fact, reason: string(item["reason"]) ?? ""))
        }
        for item in items("same") {
            guard changes < maximumChanges, case .array(let raw)? = item["ids"],
                let keep = string(item["keep"]).flatMap(EntityID.init(rawValue:))
            else {
                proposal.dropped += 1
                continue
            }
            let ids = raw.compactMap { string($0).flatMap(EntityID.init(rawValue:)) }
            guard ids.count >= 2, ids.count == raw.count, Set(ids).count == ids.count,
                ids.contains(keep), ids.allSatisfy(subjects.contains)
            else {
                proposal.dropped += 1
                continue
            }
            changes += 1
            var sure = false
            if case .bool(true)? = item["sure"] { sure = true }
            proposal.same.append(
                .init(ids: ids, keep: keep, sure: sure, reason: string(item["reason"]) ?? ""))
        }
        let suspects = Set(candidates.map(\.id))
        var renamed: Set<EntityID> = []
        for item in items("renames") {
            guard changes < maximumChanges,
                let id = string(item["id"]).flatMap(EntityID.init(rawValue:)),
                suspects.contains(id), !renamed.contains(id),
                let to = string(item["to"]).flatMap(EntityID.init(rawValue:)),
                let kind = to.rawValue.split(separator: ":").first.map(String.init),
                renameKinds.contains(kind), to != id
            else {
                proposal.dropped += 1
                continue
            }
            renamed.insert(id)
            changes += 1
            proposal.renames.append(.init(id: id, to: to, reason: string(item["reason"]) ?? ""))
        }
        for item in items("kinds") {
            guard let predicate = string(item["predicate"]), LearnedFact.isPredicate(predicate),
                !predicate.hasPrefix("memory."), mayFile(predicate), !meant.contains(predicate),
                let meaning = string(item["meaning"])
            else {
                proposal.dropped += 1
                continue
            }
            proposal.kinds.append(.init(predicate: predicate, meaning: meaning))
        }
        if case .array(let raw)? = fields["questions"] {
            proposal.questions = raw.compactMap(string)
        }
        return proposal
    }

    // MARK: - The record

    /// Every current fact a mind kept or the librarian filed, memories aside, paged.
    private func fetchKept() async throws -> [Fact] {
        var facts: [Fact] = []
        for origin in Self.origins {
            var after: FactID?
            repeat {
                let page: WorldFactPage = try await get(
                    "facts",
                    query: [
                        URLQueryItem(name: "origin_prefix", value: origin),
                        URLQueryItem(name: "limit", value: "200"),
                    ]
                        + (after.map { [URLQueryItem(name: "after_fact_id", value: $0.rawValue)] }
                            ?? []))
                facts += page.facts
                after = page.hasMore ? page.nextFactID : nil
            } while after != nil
        }
        return facts
    }

    private func fetchOverwritten(since: Date) async throws -> [OverwrittenFact] {
        var items: [OverwrittenFact] = []
        for origin in Self.origins {
            let page: OverwrittenFactPage = try await get(
                "facts/overwritten",
                query: [
                    URLQueryItem(name: "origin_prefix", value: origin),
                    URLQueryItem(name: "since", value: WorldJSON.timestamp(since)),
                    URLQueryItem(name: "limit", value: "200"),
                ])
            items += page.items
        }
        return items
    }

    private func fetchKinds() async throws -> FactKindPage {
        try await get("fact-kinds", query: [])
    }

    /// The ids that may be the wrong kind; none from a world too old to say (before 0.53.0),
    /// so the night files the rest.
    private func fetchKindCandidates() async throws -> [KindCandidate] {
        do {
            let page: KindCandidatePage = try await get("librarian/kind-candidates", query: [])
            return page.candidates
        } catch {
            logger.warning(
                "The world could not list ids that may be the wrong kind; filing without them",
                metadata: ["error": "\(error)"])
            return []
        }
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem]) async throws
        -> Value
    {
        var url = worldURL
        for part in path.split(separator: "/") { url.append(path: String(part)) }
        if !query.isEmpty { url.append(queryItems: query) }
        let request = HTTPClientRequest(url: url.absoluteString)
        let response = try await client.execute(request, timeout: .seconds(30), logger: logger)
        let body = try await response.body.collect(upTo: 16 * 1_048_576)
        guard response.status == .ok else {
            throw WorldResponderError.unavailable(status: UInt(response.status.code))
        }
        return try WorldJSON.makeDecoder().decode(Value.self, from: Data(body.readableBytesView))
    }
}

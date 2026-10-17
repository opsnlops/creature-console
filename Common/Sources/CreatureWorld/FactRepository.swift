import Foundation
import MongoKitten
import WorldCore

struct FactRepository: Sendable {
    private let facts: MongoCollection

    init(database: MongoDatabase) {
        self.facts = database[MongoWorldCollection.facts]
    }

    /// A fact is current when nothing has replaced it and its validity window, if it has one,
    /// has not closed: `scene.last` is true for an hour and then simply stops being so.
    private func currentQuery(at now: Date) -> Document {
        [
            "superseded_by": Null(),
            "$or": [
                ["valid_to": Null()] as Document,
                ["valid_to": ["$gt": now] as Document] as Document,
            ] as Document,
        ]
    }

    func save(_ fact: Fact) async throws {
        var document = try BSONEncoder().encode(fact)
        document["_id"] = fact.factID.rawValue
        // BSONEncoder drops a nil; a fact whose value is `null` ("Beaky has left") must still
        // say so, or the document has no value at all and cannot be read back.
        if fact.value == .null {
            document["value"] = Null()
        }
        document[Self.searchTextField] = Self.searchText(of: fact)
        _ = try await facts.findOneAndUpsert(
            where: ["_id": fact.factID.rawValue],
            replacement: document,
            returnValue: .modified
        )
        .writeConcern(.majority())
        .execute()
    }

    func supersede(by fact: Fact) async throws {
        _ = try await facts.updateMany(
            where: [
                "subject_id": fact.subjectID.rawValue,
                "predicate": fact.predicate,
                "superseded_by": Null(),
                "_id": ["$ne": fact.factID.rawValue],
            ],
            to: [
                "$set": [
                    "valid_to": fact.validFrom,
                    "superseded_by": fact.factID.rawValue,
                ] as Document,
                // Out of the search: history must never be what a word is scored against.
                "$unset": [Self.searchTextField: ""] as Document,
            ]
        )
    }

    /// The field the text index covers (`facts_search`).
    static let searchTextField = "search_text"

    /// The words a fact is found by: its subject, its predicate, and every string in its value
    /// - never its bookkeeping. The index used to take every string in the document, current
    /// or superseded, so "given" matched the `given-facts` producer of every fact April ever
    /// taught and a sentence with it in took five seconds, twice per utterance (#227). Ids and
    /// predicates are split into their words, so "Tamara" finds `person:tamara`.
    static func searchText(of fact: Fact) -> String {
        func spaced(_ id: String) -> String {
            String(id.map { $0.isLetter || $0.isNumber ? $0 : " " })
        }
        var words = [spaced(fact.subjectID.rawValue), spaced(fact.predicate)]
        func collect(_ value: WorldJSONValue) {
            switch value {
            case .string(let text): words.append(text)
            case .array(let values): values.forEach(collect)
            case .object(let fields): fields.keys.sorted().forEach { collect(fields[$0]!) }
            case .null, .bool, .number: break
            }
        }
        collect(fact.value)
        return words.joined(separator: " ")
    }

    /// Current facts written before `search_text` existed are given it, so the new index finds
    /// them (#227). Returns how many.
    func backfillSearchText() async throws -> Int {
        let missing: Document = [
            "superseded_by": Null(),
            Self.searchTextField: ["$exists": false] as Document,
        ]
        var count = 0
        for document in try await facts.find(missing).drain() {
            guard let id = document["_id"] as? String, let fact = try? decode(document) else {
                continue
            }
            _ = try await facts.updateOne(
                where: ["_id": id],
                to: ["$set": [Self.searchTextField: Self.searchText(of: fact)] as Document])
            count += 1
        }
        return count
    }

    /// Current facts matching `query` by MongoDB text search over each fact's words - subject,
    /// predicate, and every string in the value (`searchText(of:)`) - best first, with each
    /// fact's text score.
    /// English stemming and case-folding are the index's: "cleaner" finds "the cleaners".
    ///
    /// `own` narrows to one bird's own memories; `family` and `excluding` narrow the same way
    /// a page's query does, and `keptBy` to who said it.
    func search(
        _ query: String, own bird: EntityID? = nil, family: Family = .all,
        excluding predicates: Set<String> = [], keptBy origin: String? = nil, limit: Int,
        at now: Date
    ) async throws -> [(Fact, Double)] {
        var filter = currentQuery(at: now)
        filter["$text"] = ["$search": query] as Document
        // Only what was said by a source matching `origin` (a regex): `^(mind|librarian):` is
        // what the birds learned, never the calendar the Bridge keeps.
        if let origin { filter["origin"] = ["$regex": origin] as Document }
        // Only one bird's own memories, when retrieving for a mind.
        if let bird {
            filter["predicate"] = ["$regex": Self.ownMemoriesPattern(of: bird)] as Document
        } else if let predicate = Self.predicateFilter(family: family, excluding: predicates) {
            filter["predicate"] = predicate
        }
        let documents = try await facts.find(filter)
            .project(["score": ["$meta": "textScore"] as Document] as Document)
            .sort(["score": .textScore])
            .limit(limit)
            .drain()
        return try documents.map { document in
            (try decode(document), document["score"] as? Double ?? 0)
        }
    }

    /// One fact by id, current or not.
    func fact(withID factID: FactID) async throws -> Fact? {
        try await facts.findOne(["_id": factID.rawValue]).map(decode)
    }

    func currentFacts(subjectID: EntityID? = nil, at now: Date = Date()) async throws -> [Fact] {
        var query = currentQuery(at: now)
        if let subjectID {
            query["subject_id"] = subjectID.rawValue
        }
        let documents = try await facts.find(query).sort(["valid_from": 1]).drain()
        return try documents.map(decode)
    }

    /// Current facts about any of `subjects`, newest first, bounded.
    /// Memories are a family apart: they are fetched and trimmed on their own so a night's
    /// worth of episodes never crowds the facts of the day out of a capped page.
    enum Family: Sendable {
        case all, memories, notMemories
        /// Only what one bird remembers - its own memories, never another's.
        case own(EntityID)
        /// What a page's thirty are drawn from: not memories, and not the families folded
        /// beside them (`WorldKnowledgeLimits.foldedPrefixes`).
        case page
        /// Only the families folded beside the thirty: sensors and forecasts.
        case folded
    }

    func currentFacts(
        about subjects: [EntityID], family: Family = .all, excluding predicates: Set<String> = [],
        limit: Int, at now: Date
    ) async throws -> [Fact] {
        precondition(limit > 0)
        guard !subjects.isEmpty else { return [] }
        var query = currentQuery(at: now)
        query["subject_id"] = ["$in": subjects.map(\.rawValue)] as Document
        if let predicate = Self.predicateFilter(family: family, excluding: predicates) {
            query["predicate"] = predicate
        }
        let documents = try await facts.find(query)
            .sort(["valid_from": -1, "_id": -1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// Current facts about any of `subjects` whose kind is one of `predicates`, newest first,
    /// bounded: the kinds the words of a moment asked for, such as a bird's body (#245).
    func currentFacts(
        about subjects: [EntityID], predicates: Set<String>, limit: Int, at now: Date
    ) async throws -> [Fact] {
        precondition(limit > 0)
        guard !subjects.isEmpty, !predicates.isEmpty else { return [] }
        var query = currentQuery(at: now)
        query["subject_id"] = ["$in": subjects.map(\.rawValue)] as Document
        var kinds = Document(isArray: true)
        for name in predicates.sorted() { kinds.append(name) }
        query["predicate"] = ["$in": kinds] as Document
        let documents = try await facts.find(query)
            .sort(["valid_from": -1, "_id": -1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// The predicate half of a query for a family of facts, less the excluded kinds; nil when
    /// it narrows nothing.
    static func predicateFilter(family: Family, excluding predicates: Set<String>) -> Document? {
        var predicate: Document = [:]
        switch family {
        case .all: break
        case .memories: predicate["$regex"] = "^memory\\."
        case .own(let bird):
            predicate["$regex"] = ownMemoriesPattern(of: bird)
        case .notMemories: predicate["$not"] = ["$regex": "^memory\\."] as Document
        case .page:
            predicate["$not"] =
                ["$regex": prefixPattern(["memory."] + WorldKnowledgeLimits.foldedPrefixes)]
                as Document
        case .folded:
            predicate["$regex"] = prefixPattern(WorldKnowledgeLimits.foldedPrefixes)
        }
        // The world's own facts never take a mind's place on the page.
        if !predicates.isEmpty {
            var excluded = Document(isArray: true)
            for name in predicates.sorted() { excluded.append(name) }
            predicate["$nin"] = excluded
        }
        return predicate.isEmpty ? nil : predicate
    }

    /// `^(?:memory\.|environment\.)`: any of the prefixes.
    static func prefixPattern(_ prefixes: [String]) -> String {
        "^(?:"
            + prefixes.map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|") + ")"
    }

    // MARK: - Origin

    /// Current facts whose origin starts with `prefix` - `mind:` is every fact a bird kept -
    /// memories aside (a night's memories are a mind's too, and are not what the librarian
    /// files). Oldest first, by id, after `after`, so a long record is read in pages.
    func currentFacts(
        originPrefix prefix: String, after: FactID? = nil, limit: Int, at now: Date
    ) async throws -> [Fact] {
        precondition(limit > 0)
        var query = currentQuery(at: now)
        query["origin"] =
            ["$regex": "^" + NSRegularExpression.escapedPattern(for: prefix)] as Document
        query["predicate"] = ["$not": ["$regex": "^memory\\."] as Document] as Document
        if let after { query["_id"] = ["$gt": after.rawValue] as Document }
        let documents = try await facts.find(query).sort(["_id": 1]).limit(limit).drain()
        return try documents.map(decode)
    }

    /// What a mind kept that another keeping replaced since `since` - the same subject and
    /// predicate, a new value that is not an ending - with what replaced it. At 5:39 PM Beaky
    /// kept the instructor's gusty-wind lessons as `person.flight_training`; at 5:44 PM Mango
    /// kept something else under the same name, and the first was gone from the page (#229).
    func overwrittenFacts(originPrefix prefix: String, since: Date, limit: Int) async throws
        -> [(replaced: Fact, by: Fact)]
    {
        precondition(limit > 0)
        let origin: Document = [
            "$regex": "^" + NSRegularExpression.escapedPattern(for: prefix)
        ]
        let documents = try await facts.find([
            "origin": origin,
            "superseded_by": ["$ne": Null()] as Document,
            "valid_to": ["$gte": since] as Document,
            "predicate": ["$not": ["$regex": "^memory\\."] as Document] as Document,
        ]).sort(["valid_to": -1]).limit(limit).drain()
        let replaced = try documents.map(decode)
        let successorIDs = replaced.compactMap { $0.supersededBy?.rawValue }
        guard !successorIDs.isEmpty else { return [] }
        var ids = Document(isArray: true)
        for id in Set(successorIDs).sorted() { ids.append(id) }
        let successors = Dictionary(
            try await facts.find(["_id": ["$in": ids] as Document]).drain().map(decode)
                .map { ($0.factID, $0) },
            uniquingKeysWith: { first, _ in first })
        return replaced.compactMap { old in
            guard let id = old.supersededBy, let new = successors[id], new.value != .null,
                new.value != old.value
            else { return nil }
            return (old, new)
        }
    }

    /// Facts from before 0.49.0 are given their origin from the event they came from, while
    /// the event is still kept (#229). Returns how many.
    func backfillOrigin(events: MongoCollection) async throws -> Int {
        var count = 0
        while true {
            let batch = try await facts.find([
                "origin": ["$exists": false] as Document,
                "origin_unknown": ["$exists": false] as Document,
            ]).limit(500).drain()
            if batch.isEmpty { return count }
            var eventIDs: [String: String] = [:]
            for document in batch {
                guard let id = document["_id"] as? String,
                    let derived = document["derived_from"] as? Document,
                    let first = derived.values.first as? String, EventID(rawValue: first) != nil
                else { continue }
                eventIDs[id] = first
            }
            var wanted = Document(isArray: true)
            for id in Set(eventIDs.values).sorted() { wanted.append(id) }
            var sources: [String: String] = [:]
            for event in try await events.find(["_id": ["$in": wanted] as Document]).drain() {
                if let id = event["_id"] as? String,
                    let source = (event["source"] as? Document)?["id"] as? String
                {
                    sources[id] = source
                }
            }
            for document in batch {
                guard let id = document["_id"] as? String else { continue }
                if let event = eventIDs[id], let source = sources[event] {
                    _ = try await facts.updateOne(
                        where: ["_id": id], to: ["$set": ["origin": source] as Document])
                    count += 1
                } else {
                    // Its event is gone: said once, so the next start does not look again.
                    _ = try await facts.updateOne(
                        where: ["_id": id], to: ["$set": ["origin_unknown": true] as Document])
                }
            }
        }
    }

    /// The first filings of 2026-10-16 (World 0.52.0) began their facts at the moment of
    /// applying, so twenty-eight rewrites outranked the day's conversation on the page. Each
    /// current fact the librarian filed is dated to the newest of the facts it came from, as
    /// filings are from 0.52.1 (#229). Returns how many.
    func dateFiledFacts() async throws -> Int {
        let filed = try await facts.find([
            "producer.id": FilingReducer.producer.id,
            "superseded_by": Null(),
        ]).drain().map(decode)
        var count = 0
        for fact in filed where fact.value != .null && fact.predicate != WorldFacts.entitySameAs {
            var newest: Date?
            for case .fact(let id) in fact.derivedFrom {
                guard let source = try await self.fact(withID: id) else { continue }
                newest = max(newest ?? source.validFrom, source.validFrom)
            }
            guard let newest, newest < fact.validFrom else { continue }
            _ = try await facts.updateOne(
                where: ["_id": fact.factID.rawValue],
                to: ["$set": ["valid_from": newest] as Document])
            count += 1
        }
        return count
    }

    /// `^memory\.[a-z]+\.kenny\.`: every family of memory, Kenny's own.
    static func ownMemoriesPattern(of bird: EntityID) -> String {
        let owner = WorldFacts.memoryOwner(for: bird)
        let escaped = owner.replacingOccurrences(of: "-", with: "\\-")
        return "^memory\\.[a-z]+\\.\(escaped)\\."
    }

    /// Everything one bird remembers, on any subject, newest first: the memories resource.
    func currentFacts(rememberedBy bird: EntityID, limit: Int, at now: Date) async throws
        -> [Fact]
    {
        precondition(limit > 0)
        var query = currentQuery(at: now)
        query["predicate"] = ["$regex": Self.ownMemoriesPattern(of: bird)] as Document
        let documents = try await facts.find(query)
            .sort(["valid_from": -1, "_id": -1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// `predicatePrefix` narrows to a family - `memory.episode.kenny.2026-09-13.` is one day's
    /// episodes of one bird on every subject.
    func currentFacts(
        subjectID: EntityID?, predicatePrefix: String? = nil, after: FactID?, limit: Int,
        at now: Date
    ) async throws -> [Fact] {
        precondition(limit > 0)
        var query = currentQuery(at: now)
        if let subjectID {
            query["subject_id"] = subjectID.rawValue
        }
        if let predicatePrefix {
            query["predicate"] =
                [
                    "$regex": "^" + NSRegularExpression.escapedPattern(for: predicatePrefix)
                ] as Document
        }
        if let after {
            let greaterThan: Document = ["$gt": after.rawValue]
            query["_id"] = greaterThan
        }
        let documents = try await facts.find(query)
            .sort(["_id": 1])
            .limit(limit)
            .drain()
        return try documents.map(decode)
    }

    /// The subjects whose `predicate` (a timestamp) falls in the window - the events starting
    /// soon, soonest first.
    func subjects(withPredicate predicate: String, between from: Date, and to: Date, at now: Date)
        async throws -> [EntityID]
    {
        var query = currentQuery(at: now)
        query["predicate"] = predicate
        query["value"] =
            ["$gte": WorldJSON.timestamp(from), "$lte": WorldJSON.timestamp(to)] as Document
        let documents = try await facts.find(query).sort(["value": 1]).limit(50).drain()
        return documents.compactMap { document in
            (document["subject_id"] as? String).flatMap(EntityID.init(rawValue:))
        }
    }

    /// The current facts whose predicate is `predicate` and whose value is exactly `value` -
    /// every instance of one recurring calendar series, by its title.
    func currentFacts(withPredicate predicate: String, equalTo value: String, at now: Date)
        async throws -> [Fact]
    {
        var query = currentQuery(at: now)
        query["predicate"] = predicate
        query["value"] = value
        let documents = try await facts.find(query).limit(1_000).drain()
        return try documents.map(decode)
    }

    /// Every current fact on an id of one kind - `person:` - for the librarian's look at what
    /// may be filed as the wrong kind (#236).
    func currentFacts(subjectKind kind: String, limit: Int, at now: Date) async throws -> [Fact] {
        var query = currentQuery(at: now)
        query["subject_id"] =
            ["$regex": "^" + NSRegularExpression.escapedPattern(for: kind + ":")]
            as Document
        let documents = try await facts.find(query).limit(limit).drain()
        return try documents.map(decode)
    }

    /// Current facts anywhere whose value is `entityID`: the links into it.
    func currentFacts(pointingAt entityID: EntityID, at now: Date) async throws -> [Fact] {
        var query = currentQuery(at: now)
        query["value"] = entityID.rawValue
        let documents = try await facts.find(query).sort(["valid_from": -1]).limit(100).drain()
        return try documents.map(decode)
    }

    /// Every current fact with `predicate`, on any subject (`about` empty) or the given ones.
    func currentFacts(about subjects: [EntityID], predicate: String, limit: Int, at now: Date)
        async throws -> [Fact]
    {
        var query = currentQuery(at: now)
        query["predicate"] = predicate
        if !subjects.isEmpty {
            query["subject_id"] = ["$in": subjects.map(\.rawValue)] as Document
        }
        let documents = try await facts.find(query).limit(limit).drain()
        return try documents.map(decode)
    }

    /// The subjects that currently have a fact with `predicate` — the people the world can
    /// describe, for instance.
    func subjects(withPredicate predicate: String, at now: Date) async throws -> [EntityID] {
        var query = currentQuery(at: now)
        query["predicate"] = predicate
        let documents = try await facts.find(query).sort(["subject_id": 1]).drain()
        return documents.compactMap { document in
            (document["subject_id"] as? String).flatMap(EntityID.init(rawValue:))
        }
    }

    private func decode(_ document: Document) throws -> Fact {
        // Facts written before 0.8.0 with a `null` value have no `value` key at all, and the
        // BSON decoder cannot find a missing key; give it the null it meant.
        var readable = document
        if readable["value"] == nil {
            readable["value"] = Null()
        }
        var fact = try BSONDecoder().decode(Fact.self, from: readable)
        fact.value = try MongoWorldJSON.value(from: readable["value"] ?? Null())
        return fact
    }
}

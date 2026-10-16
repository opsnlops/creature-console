import Foundation
import WorldCore

/// Where a night's filing is reviewed and applied (#229, Ship 2): the record is loaded for
/// `FilingReviewer`, April's checked items are run past it again at the moment of applying,
/// and what still stands is cast as one `memory.filing.applied` event.
struct FilingDesk: Sendable {
    let events: WorldEventRepository
    let facts: FactRepository
    let kinds: FactKindRepository
    let accept: @Sendable (WorldEventEnvelope) async throws -> WorldEventAcceptance
    let clock: any WorldClock

    /// The most earlier applications of one filing looked through for what they applied.
    static let maximumApplications = 200

    // MARK: - Review

    func review(_ filingID: EventID) async throws -> FilingReview? {
        guard let filing = try await events.event(withID: filingID),
            let proposal = LibrarianProposal(filed: filing)
        else { return nil }
        let record = try await record(for: proposal, filing: filingID, now: await clock.now)
        let items = FilingReviewer(proposal: proposal, record: record).items
        let named = FilingReviewer.factIDs(in: proposal).union(
            items.flatMap { $0.moves + $0.stays })
        let shown = named.compactMap { id in
            record.facts[id] ?? record.kept.values.joined().first { $0.factID == id }
        }.sorted { $0.factID.rawValue < $1.factID.rawValue }
        return FilingReview(filing: filing, proposal: proposal, items: items, facts: shown)
    }

    private func record(for proposal: LibrarianProposal, filing: EventID, now: Date)
        async throws -> FilingReviewer.Record
    {
        var named: [FactID: Fact] = [:]
        for id in FilingReviewer.factIDs(in: proposal) {
            named[id] = try await facts.fact(withID: id)
        }
        var sameAs: [EntityID: EntityID] = [:]
        var kept: [EntityID: [Fact]] = [:]
        var held: [EntityID: [Fact]] = [:]
        for id in FilingReviewer.entityIDs(in: proposal) {
            let current = try await facts.currentFacts(subjectID: id, at: now)
            if let into = current.first(where: { $0.predicate == WorldFacts.entitySameAs }),
                case .string(let raw) = into.value, let keep = EntityID(rawValue: raw)
            {
                sameAs[id] = keep
            }
            kept[id] = current.filter(Self.isKept)
            held[id] = current
        }
        return FilingReviewer.Record(
            facts: named,
            meant: Set(try await kinds.meanings(of: Set(proposal.kinds.map(\.predicate))).keys),
            sameAs: sameAs, kept: kept, held: held,
            applied: try await applied(from: filing), now: now)
    }

    /// Kept by a bird or filed by the librarian: what a merge moves.
    static func isKept(_ fact: Fact) -> Bool {
        guard let origin = fact.origin?.rawValue else { return false }
        return origin.hasPrefix("mind:") || origin.hasPrefix("\(LibrarianFiling.sourceKind):")
    }

    private func applied(from filing: EventID) async throws -> Set<FilingItemKey> {
        let earlier = try await events.events(
            ofType: FilingApplication.eventType, limit: Self.maximumApplications)
        return Set(
            earlier.compactMap { try? $0.decodePayload(as: FilingApplication.self) }
                .filter { $0.filing == filing }.flatMap(\.items))
    }

    // MARK: - Apply

    func apply(_ filingID: EventID, _ selection: FilingSelection) async throws
        -> FilingApplyResult?
    {
        // The review runs again here: the Viewer's checks are what April wants, not proof the
        // record still holds them.
        guard let review = try await review(filingID) else { return nil }
        let byID = Dictionary(review.facts.map { ($0.factID, $0) }, uniquingKeysWith: { a, _ in a })
        var outcomes: [FilingOutcome] = []
        var items: [FilingItemKey] = []
        var application = FilingApplication(filing: filingID, items: [])
        var ended: Set<FactID> = []
        var merges: [(LibrarianProposal.Same, FilingReviewItem)] = []
        for key in selection.keys {
            guard let item = review.item(key), item.status == .ready else {
                let status = review.item(key)
                outcomes.append(
                    .init(
                        key: key, applied: false,
                        reason: status.map { $0.reason ?? $0.status.rawValue }
                            ?? "not in the proposal"))
                continue
            }
            switch key.list {
            case .rewrites:
                let rewrite = review.proposal.rewrites[key.index]
                let replaced = rewrite.replaces.compactMap { byID[$0] }
                application.rewrites.append(
                    .init(
                        subjectID: rewrite.subject, predicate: rewrite.predicate,
                        value: rewrite.value, validFrom: replaced.map(\.validFrom).max(),
                        validTo: item.validTo,
                        replaces: replaced.map(FilingApplication.Touched.init)))
                ended.formUnion(rewrite.replaces)
            case .retires:
                let retire = review.proposal.retires[key.index]
                guard let fact = byID[retire.fact] else { continue }
                application.retires.append(.init(fact))
                ended.insert(retire.fact)
            case .same:
                merges.append((review.proposal.same[key.index], item))
            case .kinds:
                application.kinds.append(review.proposal.kinds[key.index])
            }
            items.append(key)
            outcomes.append(.init(key: key, applied: true))
        }
        // A fact a rewrite or retire just ended does not move: that would bring it back.
        application.merges = merges.map { same, item in
            .init(
                merged: same.merged, keep: same.keep,
                moves: item.moves.filter { !ended.contains($0) }.compactMap { byID[$0] }.map(
                    FilingApplication.Move.init))
        }
        guard !items.isEmpty else { return FilingApplyResult(outcomes: outcomes, event: nil) }
        application.items = items
        let filing = review.filing
        let source = try LibrarianFiling.source(forMind: filing.source.id)
        let subjects = application.subjects
        let event = try WorldEventEnvelope(
            occurredAt: await clock.now,
            source: EventSource(
                id: source, kind: LibrarianFiling.sourceKind,
                // The same checks on the same filing are the same event: a double click
                // applies once.
                sourceEventID: "filing:\(filingID.rawValue):"
                    + items.map { "\($0.list.rawValue).\($0.index)" }.joined(separator: ",")),
            subjectIDs: subjects.isEmpty ? filing.subjectIDs : subjects,
            epistemic: EpistemicState(type: .reported, confidence: 1),
            payload: application,
            causedBy: [.event(filingID)])
        let acceptance = try await accept(event)
        if acceptance.disposition == .accepted {
            for kind in application.kinds {
                _ = try await kinds.set(
                    kind.predicate, meaning: kind.meaning, audience: nil, by: source.rawValue,
                    at: await clock.now)
            }
        }
        return FilingApplyResult(outcomes: outcomes, event: acceptance.event)
    }

    // MARK: - A merge redirects

    /// A mind keeping a fact on an id the librarian merged away has it filed on the kept id,
    /// and the event says so. One hop: a kept id is never itself merged away (the review
    /// guards it).
    func redirect(_ event: WorldEventEnvelope) async throws -> WorldEventEnvelope {
        guard event.type == GivenFactAnnouncement.eventType, event.source.kind == "mind",
            case .string(let raw)? = event.payload["subject_id"],
            let subject = EntityID(rawValue: raw),
            let into = try await facts.currentFacts(subjectID: subject, at: await clock.now)
                .first(where: { $0.predicate == WorldFacts.entitySameAs }),
            case .string(let keepRaw) = into.value, let keep = EntityID(rawValue: keepRaw),
            keep != subject
        else { return event }
        var redirected = event
        redirected.payload["subject_id"] = .string(keep.rawValue)
        redirected.payload["redirected_from"] = .string(subject.rawValue)
        redirected.subjectIDs = event.subjectIDs.map { $0 == subject ? keep : $0 }
        if !redirected.subjectIDs.contains(keep) { redirected.subjectIDs.append(keep) }
        return redirected
    }
}

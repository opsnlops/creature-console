import Foundation
import WorldCore

/// Holds a night's proposal against the record as it is now (#229, Ship 2). Pure: the record
/// is handed in, so the review April reads and the review the apply runs again are one and
/// the same code.
///
/// Two nights of proposals showed why it exists. The rewrites were good; a *sure* merge put
/// `place:workshop` - the small room in the house - together with the old pole barn, which is
/// the new workshop. Nothing is applied that April did not check, and nothing she checked is
/// applied if the record moved under it.
struct FilingReviewer: Sendable {
    /// What the proposal names, as the record holds it now.
    struct Record: Sendable {
        /// Every fact the proposal names, by id; absent when the store no longer has it.
        var facts: [FactID: Fact]
        /// The kinds that already mean something.
        var meant: Set<String>
        /// The ids already merged away, and into what.
        var sameAs: [EntityID: EntityID]
        /// For each id a merge names, the current facts a mind or the librarian kept on it.
        var kept: [EntityID: [Fact]]
        /// For each subject a rewrite names, every current fact on it, whoever said it.
        var held: [EntityID: [Fact]]
        /// Items applied before, from this filing.
        var applied: Set<FilingItemKey>
        var now: Date

        init(
            facts: [FactID: Fact] = [:], meant: Set<String> = [],
            sameAs: [EntityID: EntityID] = [:], kept: [EntityID: [Fact]] = [:],
            held: [EntityID: [Fact]] = [:], applied: Set<FilingItemKey> = [], now: Date
        ) {
            self.facts = facts
            self.meant = meant
            self.sameAs = sameAs
            self.kept = kept
            self.held = held
            self.applied = applied
            self.now = now
        }
    }

    let proposal: LibrarianProposal
    let record: Record

    /// Every fact id the proposal names - what the record must be loaded with.
    static func factIDs(in proposal: LibrarianProposal) -> Set<FactID> {
        Set(proposal.rewrites.flatMap(\.replaces) + proposal.retires.map(\.fact))
    }

    /// Every entity id the proposal names.
    static func entityIDs(in proposal: LibrarianProposal) -> Set<EntityID> {
        Set(proposal.same.flatMap(\.ids) + proposal.rewrites.map(\.subject))
    }

    var items: [FilingReviewItem] {
        proposal.rewrites.indices.map(rewrite) + proposal.retires.indices.map(retire)
            + proposal.same.indices.map(same) + proposal.kinds.indices.map(kind)
    }

    // MARK: - The four lists

    private func rewrite(_ index: Int) -> FilingReviewItem {
        let key = FilingItemKey(.rewrites, index)
        let item = proposal.rewrites[index]
        if record.applied.contains(key) { return applied(key) }
        if let stale = staleness(of: item.replaces) { return .init(key: key, stale) }
        let replaced = item.replaces.compactMap { record.facts[$0] }
        if let guarded = protection(of: [item.predicate] + replaced.map(\.predicate)) {
            return .init(key: key, guarded)
        }
        if let into = record.sameAs[item.subject] {
            return .init(
                key: key, .guarded("\(item.subject.rawValue) was merged into \(into.rawValue)"))
        }
        // A name holds one value: writing it would end what is there, so what is there must be
        // among what the rewrite folds in.
        if let held = record.held[item.subject]?.first(where: {
            $0.predicate == item.predicate && $0.value != .null
                && !item.replaces.contains($0.factID)
        }) {
            return .init(
                key: key,
                .guarded(
                    "\(item.predicate) already holds \(held.factID.rawValue), which it does not fold in"
                ))
        }
        return FilingReviewItem(
            key: key, status: .ready, checked: true,
            validTo: replaced.compactMap(\.validTo).min())
    }

    private func retire(_ index: Int) -> FilingReviewItem {
        let key = FilingItemKey(.retires, index)
        let item = proposal.retires[index]
        if record.applied.contains(key) { return applied(key) }
        if let stale = staleness(of: [item.fact]) { return .init(key: key, stale) }
        if let fact = record.facts[item.fact], let guarded = protection(of: [fact.predicate]) {
            return .init(key: key, guarded)
        }
        return FilingReviewItem(key: key, status: .ready, checked: true)
    }

    private func same(_ index: Int) -> FilingReviewItem {
        let key = FilingItemKey(.same, index)
        let item = proposal.same[index]
        if record.applied.contains(key) { return applied(key) }
        if let bird = item.ids.first(where: { $0.rawValue.hasPrefix("character:") }) {
            return .init(key: key, .guarded("\(bird.rawValue) is a bird; birds are never merged"))
        }
        if let merged = item.ids.first(where: { record.sameAs[$0] != nil }) {
            return .init(
                key: key,
                .guarded(
                    "\(merged.rawValue) was already merged into \(record.sameAs[merged]!.rawValue)")
            )
        }
        // What the kept id already holds stays its own; the merged ids' other facts move.
        let held = Set((record.kept[item.keep] ?? []).map(\.predicate))
        var moves: [FactID] = []
        var stays: [FactID] = []
        for id in item.merged {
            for fact in record.kept[id] ?? [] where Self.moves(fact) {
                if held.contains(fact.predicate) {
                    stays.append(fact.factID)
                } else {
                    moves.append(fact.factID)
                }
            }
        }
        return FilingReviewItem(
            key: key, status: .ready,
            reason: item.sure ? nil : "not sure: April's to decide", checked: item.sure,
            moves: moves, stays: stays)
    }

    private func kind(_ index: Int) -> FilingReviewItem {
        let key = FilingItemKey(.kinds, index)
        let item = proposal.kinds[index]
        if record.applied.contains(key) { return applied(key) }
        if let guarded = protection(of: [item.predicate]) { return .init(key: key, guarded) }
        if record.meant.contains(item.predicate) {
            return .init(
                key: key,
                .guarded("\(item.predicate) already has a meaning; a Wizard can reword it"))
        }
        return FilingReviewItem(key: key, status: .ready, checked: true)
    }

    // MARK: - The checks

    /// A memory is the bird's own and stays where it was remembered; a protected kind keeps
    /// its own rules. Everything else a mind kept on a merged id moves.
    static func moves(_ fact: Fact) -> Bool {
        !fact.predicate.hasPrefix("memory.") && !LibrarianFiling.isProtected(fact.predicate)
            && fact.predicate != WorldFacts.entitySameAs
    }

    private func staleness(of ids: [FactID]) -> Verdict? {
        for id in ids {
            guard let fact = record.facts[id] else {
                return .stale("\(id.rawValue) is no longer in the record")
            }
            if !Self.isCurrent(fact, at: record.now) {
                return .stale(
                    "\(fact.subjectID.rawValue) \(fact.predicate) changed since the night")
            }
        }
        return nil
    }

    static func isCurrent(_ fact: Fact, at now: Date) -> Bool {
        fact.supersededBy == nil && fact.value != .null && (fact.validTo.map { $0 > now } ?? true)
    }

    private func protection(of predicates: [String]) -> Verdict? {
        predicates.first(where: LibrarianFiling.isProtected).map {
            .guarded("\($0) has its own rules; the librarian does not file it")
        }
    }

    private func applied(_ key: FilingItemKey) -> FilingReviewItem {
        FilingReviewItem(key: key, status: .applied, checked: false)
    }

    enum Verdict {
        case stale(String)
        case guarded(String)
    }
}

extension FilingReviewItem {
    fileprivate init(key: FilingItemKey, _ verdict: FilingReviewer.Verdict) {
        switch verdict {
        case .stale(let reason): self.init(key: key, status: .stale, reason: reason, checked: false)
        case .guarded(let reason):
            self.init(key: key, status: .guarded, reason: reason, checked: false)
        }
    }
}

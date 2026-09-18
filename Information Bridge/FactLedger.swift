import Foundation
import WorldCore

/// What a source has said about each of its items, and to which entity - so a source can cast
/// only what changed, take back what went away, and move what was mapped elsewhere. One file
/// per source on this Mac. Shared by the address book and the calendar; any source that turns
/// items into facts on entities.
actor FactLedger {
    struct Entry: Codable, Equatable, Sendable {
        var entityID: EntityID
        var facts: [String: WorldJSONValue]
    }

    /// What a source wants the world to hold about one item now.
    struct Wanted: Equatable, Sendable {
        var entityID: EntityID
        var facts: [String: WorldJSONValue]
        var validUntil: Date?
    }

    typealias Cast = @Sendable (WorldEventEnvelope) async throws -> Void

    let source: String
    private let file: URL
    private(set) var entries: [String: Entry] = [:]

    init(source: String, directory: URL) {
        self.source = source
        // A ledger that cannot be written is a Bridge that says it all again next start.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "\(source)-ledger.json")
        if let data = try? Data(contentsOf: file),
            let saved = try? WorldJSON.makeDecoder().decode([String: Entry].self, from: data)
        {
            entries = saved
        }
    }

    /// Brings the world to `wanted`: casts new and changed facts, takes back facts that went
    /// away and items that are gone, moves an item whose entity changed. Returns how many
    /// facts were cast. A cast that fails leaves the ledger as it was for that fact, so it is
    /// tried again next time. With `keepingMissing`, items not in `wanted` are left alone - a
    /// source part-way through reading everything again has not yet got to them.
    func reconcile(
        _ wanted: [String: Wanted], now: Date, keepingMissing: Bool = false,
        held: [EntityID: Set<String>]? = nil, cast: Cast
    ) async -> Int {
        var count = 0
        for (item, want) in wanted {
            if let had = entries[item], had.entityID != want.entityID {
                // Mapped to someone else now: everything on the old entity is taken back first.
                for predicate in had.facts.keys {
                    if await retract(had.entityID, predicate, item: item, now: now, cast: cast) {
                        entries[item]?.facts[predicate] = nil
                    }
                }
                entries[item] = nil
            }
            let had = entries[item]?.facts ?? [:]
            // A fact the world does not hold is cast again whatever this ledger remembers:
            // the world is the truth the ledger must match, in both directions.
            let missing = held.map { $0[want.entityID] ?? [] }
            for (predicate, value) in want.facts
            where had[predicate] != value || missing.map({ !$0.contains(predicate) }) == true {
                if await send(
                    want.entityID, predicate, value, validUntil: want.validUntil, item: item,
                    now: now, cast: cast)
                {
                    entries[item, default: Entry(entityID: want.entityID, facts: [:])]
                        .facts[predicate] = value
                    count += 1
                }
            }
            for predicate in had.keys where want.facts[predicate] == nil {
                if await retract(want.entityID, predicate, item: item, now: now, cast: cast) {
                    entries[item]?.facts[predicate] = nil
                }
            }
            // Written as it goes: a source restarted mid-way must not say it all again.
            if count > 0, count % 25 == 0 { save() }
        }
        for (item, had) in entries where wanted[item] == nil && !keepingMissing {
            var remaining = had.facts
            for predicate in had.facts.keys {
                if await retract(had.entityID, predicate, item: item, now: now, cast: cast) {
                    remaining[predicate] = nil
                }
            }
            entries[item] =
                remaining.isEmpty ? nil : Entry(entityID: had.entityID, facts: remaining)
        }
        save()
        return count
    }

    /// Takes back facts the world holds that no item of this source wants - ghosts from a
    /// ledger that never knew them (another Mac's Bridge cast them). Returns how many facts
    /// were retracted. Nothing is recorded: there was no entry, and there is none after.
    func retractGhosts(_ ghosts: [EntityID: [String]], now: Date, cast: Cast) async -> Int {
        var count = 0
        for (entity, predicates) in ghosts {
            for predicate in predicates {
                if await retract(
                    entity, predicate, item: "ghost:\(entity.rawValue)", now: now, cast: cast)
                {
                    count += 1
                }
            }
        }
        return count
    }

    /// Lets items go without taking anything back: their facts carried a `valid_to` the world
    /// has already honoured, so there is nothing left to retract.
    func forget(_ items: Set<String>) {
        for item in items { entries[item] = nil }
        save()
    }

    private func send(
        _ entity: EntityID, _ predicate: String, _ value: WorldJSONValue, validUntil: Date?,
        item: String, now: Date, cast: Cast
    ) async -> Bool {
        do {
            let itemID = "\(item):\(predicate):\(WorldJSON.timestamp(now))"
            let event =
                if let validUntil {
                    try BridgeFacts.given(
                        subject: entity, predicate: predicate, value: value,
                        validUntil: validUntil, source: source, itemID: itemID, at: now)
                } else {
                    try BridgeFacts.given(
                        subject: entity, predicate: predicate, value: value, validFor: nil,
                        source: source, itemID: itemID, at: now)
                }
            try await cast(event)
            return true
        } catch {
            return false
        }
    }

    private func retract(
        _ entity: EntityID, _ predicate: String, item: String, now: Date, cast: Cast
    ) async -> Bool {
        do {
            try await cast(
                try BridgeFacts.given(
                    subject: entity, predicate: predicate, value: .null, validFor: 1,
                    source: source, itemID: "\(item):\(predicate):gone:\(WorldJSON.timestamp(now))",
                    at: now))
            return true
        } catch {
            return false
        }
    }

    private func save() {
        try? WorldJSON.makeEncoder().encode(entries).write(to: file, options: .atomic)
    }
}

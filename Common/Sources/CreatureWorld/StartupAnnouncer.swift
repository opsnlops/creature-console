import Foundation
import WorldCore

/// What the world assumes about people and what `world.json` says, announced at every start
/// (#260). Each fills a blank and never replaces evidence. The announcements are the same events
/// on every restart, and since 0.64.1 an old duplicate is never reduced again (#259). But events
/// live ninety days: once the first announcement has gone, a restart's is a new event, and
/// "assumed home" would supersede what the house saw - around 2026-12-12 for the 2026-09-13 one.
/// So an assumption is cast only for a person whose presence is unknown or itself assumed, and a
/// configured fact only where nothing but the configuration has spoken.
struct StartupAnnouncer: Sendable {
    let facts: FactRepository
    let accept: @Sendable (WorldEventEnvelope) async throws -> Void

    /// Casts what fills a blank; returns how many were cast and how many evidence already held.
    @discardableResult
    func announce(presence: PresenceConfiguration, givenFacts: [GivenFact], at now: Date)
        async throws -> (cast: Int, skipped: Int)
    {
        var cast = 0
        var skipped = 0
        for event in try AssumedPresenceAnnouncement.events(for: presence, at: now)
            + GivenFactAnnouncement.events(for: givenFacts, at: now)
        {
            guard try await fillsIn(event, at: now) else {
                skipped += 1
                continue
            }
            try await accept(event)
            cast += 1
        }
        return (cast, skipped)
    }

    /// Whether `event` speaks where nothing but an announcement has: an assumption over no
    /// presence or an older assumption, a configured fact over none or the configuration's own.
    func fillsIn(_ event: WorldEventEnvelope, at now: Date) async throws -> Bool {
        switch event.type {
        case AssumedPresenceAnnouncement.eventType:
            guard case .string(let raw)? = event.payload["person_id"],
                let person = EntityID(rawValue: raw)
            else { return true }
            let state = try await facts.currentFacts(subjectID: person, at: now)
                .first { $0.predicate == WorldFacts.personState }
            return state.map { $0.epistemic.type == .assumed } ?? true
        case GivenFactAnnouncement.eventType:
            guard case .string(let raw)? = event.payload["subject_id"],
                let subject = EntityID(rawValue: raw),
                case .string(let predicate)? = event.payload["predicate"]
            else { return true }
            let held = try await facts.currentFacts(subjectID: subject, at: now)
                .first { $0.predicate == predicate }
            return held.map { $0.origin == GivenFactAnnouncement.sourceID } ?? true
        default:
            return true
        }
    }
}

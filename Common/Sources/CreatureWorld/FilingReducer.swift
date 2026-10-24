import Foundation
import WorldCore

/// `memory.filing.applied` → the record, filed (#229, Ship 2). The event carries what April
/// checked, already resolved against the record - each replaced fact's subject and predicate,
/// each moved fact's value - so this stays pure, like every reducer.
///
/// - A rewrite is the new fact, derived from the event and every fact it replaces, so Why?
///   walks back to them; each replaced name that is not the new one is ended.
/// - A retire ends its fact.
/// - A merge marks each merged id `entity.same_as` the kept one, and moves what the minds kept
///   there: given on the kept id, ended on the merged.
///
/// Kinds are the glossary's, not facts; the service writes them.
struct FilingReducer: WorldReducer {
    let eventTypes: Set<WorldEventType> = [FilingApplication.eventType]

    static let producer = FactProducer(
        kind: PresenceFacts.producerKind, id: "librarian", version: "1")

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction {
        let application = try event.decodePayload(as: FilingApplication.self)
        var facts: [Fact] = []
        for rewrite in application.rewrites {
            for replaced in rewrite.replaces
            where (replaced.subjectID, replaced.predicate) != (rewrite.subjectID, rewrite.predicate)
            {
                facts.append(try Self.ending(replaced, by: event))
            }
            facts.append(
                try Fact(
                    subjectID: rewrite.subjectID,
                    predicate: rewrite.predicate,
                    value: .string(rewrite.value),
                    epistemic: event.epistemic,
                    validFrom: Self.start(rewrite.validFrom, by: event),
                    validTo: rewrite.validTo,
                    derivedFrom: [.event(event.eventID)]
                        + rewrite.replaces.map { .fact($0.factID) },
                    producer: Self.producer,
                    origin: event.source.id))
        }
        for retired in application.retires {
            facts.append(try Self.ending(retired, by: event))
        }
        for merge in application.merges {
            for merged in merge.merged {
                facts.append(
                    try Fact(
                        subjectID: merged,
                        predicate: WorldFacts.entitySameAs,
                        value: .string(merge.keep.rawValue),
                        epistemic: event.epistemic,
                        validFrom: event.occurredAt,
                        derivedFrom: [.event(event.eventID)],
                        producer: Self.producer,
                        origin: event.source.id))
            }
            for move in merge.moves {
                facts.append(try Self.ending(move.fact, by: event))
                facts.append(
                    try Fact(
                        subjectID: merge.keep,
                        predicate: move.fact.predicate,
                        value: move.value,
                        epistemic: event.epistemic,
                        validFrom: Self.start(move.validFrom, by: event),
                        validTo: move.validTo,
                        derivedFrom: [.event(event.eventID), .fact(move.fact.factID)],
                        producer: Self.producer,
                        origin: event.source.id,
                        aloneWith: move.aloneWith))
            }
        }
        return WorldReduction(changedFacts: facts)
    }

    /// When a filed fact begins: as old as what it came from, never later than the filing -
    /// and the filing's moment for an application recorded before the date was carried.
    static func start(_ date: Date?, by event: WorldEventEnvelope) -> Date {
        min(date ?? event.occurredAt, event.occurredAt)
    }

    /// The `null` that ends a filed-away fact, as a retraction's ending does: from the event,
    /// gone again a second later, pointing at what it ended.
    static func ending(_ fact: FilingApplication.Touched, by event: WorldEventEnvelope) throws
        -> Fact
    {
        try Fact(
            subjectID: fact.subjectID,
            predicate: fact.predicate,
            value: .null,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: event.occurredAt,
            validTo: event.occurredAt.addingTimeInterval(1),
            derivedFrom: [.event(event.eventID), .fact(fact.factID)],
            producer: producer,
            origin: event.source.id)
    }
}

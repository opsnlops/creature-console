import WorldCore

protocol WorldReducer: Sendable {
    var eventTypes: Set<WorldEventType> { get }

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction
}

struct WorldReduction: Equatable, Sendable {
    var changedFacts: [Fact]
    var derivedEvents: [WorldEventEnvelope]
    /// Facts the reducer wants gone without knowing them by name - it sees one event, never
    /// the world's current state, so the world resolves these against the store.
    var retractions: [FactRetraction]

    init(
        changedFacts: [Fact] = [],
        derivedEvents: [WorldEventEnvelope] = [],
        retractions: [FactRetraction] = []
    ) {
        self.changedFacts = changedFacts
        self.derivedEvents = derivedEvents
        self.retractions = retractions
    }
}

/// "The virtual world can guess, but the real world knows": when something is observed, what
/// was merely *reported* about the same thing is moot. Every current fact on `subjectID` whose
/// predicate starts with `predicatePrefix`, was told to the world (`reported` - a bird's
/// learning, a wizard's word) rather than observed or assumed, and is not one of `except`, is
/// closed by a `null` fact derived from the event, so Why? shows what ended it.
struct FactRetraction: Equatable, Sendable {
    var subjectID: EntityID
    var predicatePrefix: String
    var except: Set<String>
    var producer: FactProducer

    func covers(_ fact: Fact) -> Bool {
        fact.subjectID == subjectID && fact.predicate.hasPrefix(predicatePrefix)
            && !except.contains(fact.predicate) && fact.epistemic.type == .reported
            && fact.value != .null
    }

    /// The fact that ends `fact`: `null`, from `event`, gone again a second later.
    func ending(_ fact: Fact, by event: WorldEventEnvelope) throws -> Fact {
        try Fact(
            subjectID: fact.subjectID,
            predicate: fact.predicate,
            value: .null,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            validFrom: event.occurredAt,
            validTo: event.occurredAt.addingTimeInterval(1),
            derivedFrom: [.event(event.eventID), .fact(fact.factID)],
            producer: producer
        )
    }
}

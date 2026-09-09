import WorldCore

protocol WorldReducer: Sendable {
    var eventTypes: Set<WorldEventType> { get }

    func reduce(_ event: WorldEventEnvelope) throws -> WorldReduction
}

struct WorldReduction: Equatable, Sendable {
    var changedFacts: [Fact]
    var derivedEvents: [WorldEventEnvelope]

    init(
        changedFacts: [Fact] = [],
        derivedEvents: [WorldEventEnvelope] = []
    ) {
        self.changedFacts = changedFacts
        self.derivedEvents = derivedEvents
    }
}

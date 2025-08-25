import Combine
import Common
import Foundation
import OSLog

struct CreatureCacheState: Sendable {
    let creatures: [CreatureIdentifier: Creature]
    let empty: Bool
}

actor CreatureCache {
    static let shared = CreatureCache()

    private var creatures: [CreatureIdentifier: Creature] = [:]
    private var empty: Bool = true

    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureCache")

    // AsyncStream for UI updates
    private let (stateStream, stateContinuation) = AsyncStream.makeStream(
        of: CreatureCacheState.self)

    var stateUpdates: AsyncStream<CreatureCacheState> {
        stateStream
    }

    // Make sure we don't accidentally create two of these
    private init() {}


    func addCreature(_ creature: Creature, for id: CreatureIdentifier) {
        creatures[id] = creature
        empty = creatures.isEmpty
        publishState()
    }

    private func publishState() {
        let currentState = CreatureCacheState(
            creatures: creatures,
            empty: empty
        )
        stateContinuation.yield(currentState)
    }

    func removeCreature(for id: CreatureIdentifier) {
        creatures.removeValue(forKey: id)
        empty = creatures.isEmpty
        publishState()
    }

    public func reload(with creatures: [Creature]) {
        let reloadedCreatures = Dictionary(uniqueKeysWithValues: creatures.map { ($0.id, $0) })
        self.creatures = reloadedCreatures
        self.empty = reloadedCreatures.isEmpty
        publishState()
    }

    public func getById(id: CreatureIdentifier) -> Result<Creature, ServerError> {
        if let creature = creatures[id] {
            return .success(creature)
        } else {
            logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
            return .failure(.notFound("Creature ID \(id) not found in the cache"))
        }
    }

    public var count: Int {
        return creatures.count
    }

    public func getCurrentState() -> CreatureCacheState {
        return CreatureCacheState(creatures: creatures, empty: empty)
    }
}

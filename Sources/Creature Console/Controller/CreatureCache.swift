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

    private var continuations: [UUID: AsyncStream<CreatureCacheState>.Continuation] = [:]

    var stateUpdates: AsyncStream<CreatureCacheState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { [weak self] in
                await self?.addContinuation(id: id, continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    // Make sure we don't accidentally create two of these
    private init() {}

    func addCreature(_ creature: Creature, for id: CreatureIdentifier) {
        self.creatures[id] = creature
        self.empty = self.creatures.isEmpty
        self.logger.debug("CreatureCache: Added/Updated creature \(id); count: \(self.creatures.count), empty: \(self.empty)")
        self.publishState()
    }

    private func currentSnapshot() -> CreatureCacheState {
        CreatureCacheState(
            creatures: self.creatures,
            empty: self.empty
        )
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<CreatureCacheState>.Continuation) {
        self.continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(self.currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        self.continuations[id] = nil
    }

    private func publishState() {
        let snapshot = self.currentSnapshot()
        self.logger.debug("CreatureCache: Broadcasting state (count: \(self.creatures.count), empty: \(self.empty))")
        for continuation in self.continuations.values {
            continuation.yield(snapshot)
        }
    }

    func removeCreature(for id: CreatureIdentifier) {
        self.creatures.removeValue(forKey: id)
        self.empty = self.creatures.isEmpty
        self.logger.debug("CreatureCache: Removed creature \(id); count: \(self.creatures.count), empty: \(self.empty)")
        self.publishState()
    }

    public func reload(with creatures: [Creature]) {
        let reloadedCreatures = Dictionary(uniqueKeysWithValues: creatures.map { ($0.id, $0) })
        self.creatures = reloadedCreatures
        self.empty = reloadedCreatures.isEmpty
        self.logger.info("CreatureCache: Reloaded with \(self.creatures.count) creatures (empty: \(self.empty))")
        self.publishState()
    }

    public func getById(id: CreatureIdentifier) -> Result<Creature, ServerError> {
        if let creature = self.creatures[id] {
            return .success(creature)
        } else {
            self.logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
            return .failure(.notFound("Creature ID \(id) not found in the cache"))
        }
    }

    public var count: Int {
        return self.creatures.count
    }

    public func getCurrentState() -> CreatureCacheState {
        return CreatureCacheState(creatures: self.creatures, empty: self.empty)
    }
}

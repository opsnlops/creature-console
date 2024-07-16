import Combine
import Common
import Foundation
import OSLog

class CreatureCache: ObservableObject {
    static let shared = CreatureCache()

    @Published public private(set) var creatures: [CreatureIdentifier: Creature] = [:]
    @Published public private(set) var empty: Bool = true

    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureCache")
    private let queue = DispatchQueue(label: "io.opsnlops.CreatureConsole.CreatureCache.queue", attributes: .concurrent)

    // Make sure we don't accidentally create two of these
    private init() {}


    func addCreature(_ creature: Creature, for id: CreatureIdentifier) {
        queue.async(flags: .barrier) {
            var updatedCreatures = self.creatures
            updatedCreatures[id] = creature
            DispatchQueue.main.async {
                self.creatures = updatedCreatures
                self.empty = updatedCreatures.isEmpty
            }
        }
    }

    func removeCreature(for id: CreatureIdentifier) {
        queue.async(flags: .barrier) {
            var updatedCreatures = self.creatures
            updatedCreatures.removeValue(forKey: id)
            DispatchQueue.main.async {
                self.creatures = updatedCreatures
                self.empty = updatedCreatures.isEmpty
            }
        }
    }

    public func reload(with creatures: [Creature]) {
        queue.async(flags: .barrier) {
            let reloadedCreatures = Dictionary(uniqueKeysWithValues: creatures.map { ($0.id, $0) })
            DispatchQueue.main.async {
                self.creatures = reloadedCreatures
                self.empty = reloadedCreatures.isEmpty
            }
        }
    }

    public func getById(id: CreatureIdentifier) -> Result<Creature, ServerError> {
        queue.sync {
            if let creature = creatures[id] {
                return .success(creature)
            } else {
                logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
                return .failure(.notFound("Creature ID \(id) not found in the cache"))
            }
        }
    }
}

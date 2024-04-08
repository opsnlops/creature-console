
import Foundation
import SwiftUI
import OSLog


/**
 This is designed to live in the Environment, as a store of the Creatures that we know exist
 */
class CreatureCache : ObservableObject {
    @Published var creatures : [Creature]
    @Published var empty : Bool = true
   
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "CreatureList")
    
    init() {
        creatures = []
    }
    
    func getById(id: Data) -> Creature {
        for c in creatures {
            if c.id == id {
                return c
            }
        }
        logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
        
        return Creature.mock()
    }
    
    func add(item: Creature) {
        creatures.append(item)
        empty = false
    }
}




extension CreatureCache {
    static func mock() -> CreatureCache {
        let creaureList = CreatureCache()

        let id1 = Creature.mock()
        id1.name = "Creature 1 🦜"

        let id2 = Creature.mock()
        id2.name = "Creature 2 🦖"

        let id3 = Creature.mock()
        id3.name = "Creature 3 🐰"

        creaureList.add(item: id1)
        creaureList.add(item: id2)
        creaureList.add(item: id3)
        
        return creaureList
    }
}

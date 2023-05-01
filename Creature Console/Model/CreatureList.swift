//
//  CreatureList.swift
//  Creature Console
//
//  Created by April White on 4/8/23.
//

import Foundation
import SwiftUI
import Logging


/**
 This is designed to live in the Environment, as a store of the Creatures that we know exist
 */
class CreatureList : ObservableObject {
    @Published var creatures : [Creature]
    @Published var empty : Bool = true
   
    let logger = Logger(label: "CreatureList")
    
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




extension CreatureList {
    static func mock() -> CreatureList {
        let creaureList = CreatureList()
        
        let id1 = Creature.mock()
        id1.name = "Creature 1 🦜"
        id1.id = DataHelper.generateRandomData(byteCount: 12)
        
        let id2 = Creature.mock()
        id2.name = "Creature 2 🦖"
        id2.id = DataHelper.generateRandomData(byteCount: 12)
        
        let id3 = Creature.mock()
        id3.name = "Creature 3 🐰"
        id3.id = DataHelper.generateRandomData(byteCount: 12)
    
        creaureList.add(item: id1)
        creaureList.add(item: id2)
        creaureList.add(item: id3)
        
        return creaureList
    }
}

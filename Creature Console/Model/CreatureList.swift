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

//
//  CreatureList.swift
//  Creature Console
//
//  Created by April White on 4/8/23.
//

import Foundation
import SwiftUI


/**
 This is designed to live in the Environment, as a store of the Creatures that we know exist
 */
class CreatureList : ObservableObject {
    @Published var ids : [CreatureIdentifier]
    @Published var empty : Bool = true
   
    init() {
        ids = []
    }
    
    func add(item: CreatureIdentifier) {
        ids.append(item)
        empty = false
    }
}

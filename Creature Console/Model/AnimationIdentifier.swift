//
//  AnimationIdentifier.swift
//  Creature Console
//
//  Created by April White on 4/30/23.
//

import Foundation



struct AnimationIdentifier : Hashable, Equatable {
    static func == (lhs: AnimationIdentifier, rhs: AnimationIdentifier) -> Bool {
        if lhs.id == rhs.id {
            return true
        }
        
        return false
    }
        
    let id: Data
    let metadata: Animation.Metadata

    init(id: Data, metadata: Animation.Metadata) {
        self.id = id
        self.metadata = metadata
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
}

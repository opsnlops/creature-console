//
//  AnimationIdentifier.swift
//  Creature Console
//
//  Created by April White on 4/30/23.
//

import Foundation



class AnimationIdentifier : Hashable, Equatable, ObservableObject {
        
    let id: Data
    let metadata: Animation.Metadata

    init(id: Data, metadata: Animation.Metadata) {
        self.id = id
        self.metadata = metadata
    }

    init(serverAnimationIdentifier: Server_AnimationIdentifier) {
        self.id = serverAnimationIdentifier.id
        self.metadata = Animation.Metadata(serverAnimationMetadata: serverAnimationIdentifier.metadata)
    }

    static func == (lhs: AnimationIdentifier, rhs: AnimationIdentifier) -> Bool {
        if lhs.id == rhs.id {
            return true
        }
        
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
}

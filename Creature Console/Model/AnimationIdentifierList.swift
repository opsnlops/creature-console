//
//  AnimationIdentifierList.swift
//  Creature Console
//
//  Created by April White on 4/23/23.
//

import Foundation
import SwiftUI
import Logging


/**
 This is designed to live in the Environment, as a store of the Animations that we know exist
 */
class AnimationIdentifier : ObservableObject {
    @Published var animations : [Server_AnimationIdentifier]
    @Published var empty : Bool = true
   
    let logger = Logger(label: "AnimationIdentifier")
    
    init() {
        animations = []
    }
    
    func getById(id: Data) -> Server_AnimationIdentifier {
        for a in animations {
            if a.id == id {
                return a
            }
        }
        logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
        
        return Server_AnimationIdentifier()
    }
    
    func add(item: Server_AnimationIdentifier) {
        animations.append(item)
        empty = false
    }
}

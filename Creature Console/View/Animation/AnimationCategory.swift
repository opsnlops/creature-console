//
//  AnimationCategory.swift
//  Creature Console
//
//  Created by April White on 4/30/23.
//

import SwiftUI

struct AnimationCategory: View {
    let creatureType: CreatureType
    
    var body: some View {
        Text(creatureType.description)
    }
}

struct AnimationCategory_Previews: PreviewProvider {
    static var previews: some View {
        AnimationCategory(creatureType: .parrot)
    }
}

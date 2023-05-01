//
//  AnimationCategory.swift
//  Creature Console
//
//  Created by April White on 4/30/23.
//

import SwiftUI

struct AnimationCategory: View {
    
    @EnvironmentObject var client: CreatureServerClient    
    @State var creatureType: CreatureType
    @State var animationIds : [AnimationIdentifier]?
    
    var body: some View {
        VStack {
            
            if let ids = animationIds {
                ForEach(ids, id: \.self) { id in
                    Text(id.metadata.title)
                    }
            }
            else {
                Text("Loading animations for type \(creatureType.description)...")
            }
               
        }
        .onAppear {
            loadData()
        }
        .onChange(of: creatureType) { _ in
            loadData()
        }
    }
    
    func loadData() {
        animationIds = nil
        
      Task {
          // Go load the animations
          let result = await client.listAnimations(creatureType: creatureType.protobufValue)
          
          switch(result) {
          case .success(let data):
              animationIds = data
          case .failure(let error):
              print("Error: \(String(describing: error.errorDescription))")
              
          }
      }
    }
}

struct AnimationCategory_Previews: PreviewProvider {
    static var previews: some View {
        AnimationCategory(creatureType: .parrot)
    }
}

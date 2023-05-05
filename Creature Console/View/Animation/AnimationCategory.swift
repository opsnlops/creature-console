//
//  AnimationCategory.swift
//  Creature Console
//
//  Created by April White on 4/30/23.
//

import SwiftUI
import Logging

struct AnimationCategory: View {
    
    @EnvironmentObject var client: CreatureServerClient    
    @Binding var creatureType: CreatureType?
    @State var animationIds : [AnimationIdentifier]?
    let logger = Logger(label: "AnimationCategory")
    
    var body: some View {
        VStack {
            if let ids = animationIds {
                ForEach(ids, id: \.self) { id in
                    Text(id.metadata.title)
                    }
            }
            else {
                Text("Loading animations for type \(creatureType?.description ?? "unknown")...")
            }
               
        }
        .onAppear {
            logger.info("onAppear()")
            loadData()
        }
        .onChange(of: creatureType) { _ in
            logger.info("onChange()")
            loadData()
        }
    }
    
    func loadData() {
      Task {
          // Go load the animations
          if let pValue = creatureType?.protobufValue {
              let result = await client.listAnimations(creatureType: pValue)
              logger.debug("got it")
              
              switch(result) {
              case .success(let data):
                  logger.debug("success!")
                  self.animationIds = data
              case .failure(let error):
                  print("Error: \(String(describing: error.errorDescription))")
                  
              }
          }
          else {
              print("pValue is nil")
          }
      }
    }
}


struct AnimationCategory_Previews: PreviewProvider {
    static var previews: some View {
        AnimationCategory(creatureType: .constant(CreatureType.parrot))
            .environmentObject(CreatureServerClient.mock())
    }
}

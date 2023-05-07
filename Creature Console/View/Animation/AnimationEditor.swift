//
//  AnimationEditor.swift
//  Creature Console
//
//  Created by April White on 5/6/23.
//

import SwiftUI
import Logging


// This is the main animation editor for all of the Animations

struct AnimationEditor: View {
    
    private var creature : Creature
    private var animation : Animation?
    
    let logger = Logger(label: "Animtion Editor")
    
    @State private var title : String = ""
    @State private var notes : String = ""
    @State private var audioFile : String = ""
    
    init(creature: Creature, animation: Animation) {
        self.creature = creature
        self.animation = animation
        

        logger.info("New AnimationEditor made")
    }
    
    var body: some View {
        
        VStack {
            Form {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }
           
            
            
        }.navigationTitle("Animation Editor")
        
        
    }
}

struct AnimationEditor_Previews: PreviewProvider {
    static var previews: some View {
        AnimationEditor(creature: .mock(), animation: .mock())
    }
}

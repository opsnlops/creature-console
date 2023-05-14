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
    
    var animationId: Data?
    
    @EnvironmentObject var client: CreatureServerClient
    
    @State var creature : Creature?
    @State var animation : Animation?
    
    
    let logger = Logger(label: "Animtion Editor")
    
    @State private var title : String = ""
    @State private var notes : String = ""
    @State private var audioFile : String = ""
    
   
    var body: some View {
        
        VStack {
            Form {
                TextField("Title", text: $title.onChange(updateAnimationTitle))
                    .textFieldStyle(.roundedBorder)
                    
                TextField("Notes", text: $notes.onChange(updateAnimationNotes))
                    .textFieldStyle(.roundedBorder)
                
                
            }
            
            if let a = animation {
                ViewAnimation(animation: a)
            }
           
        }
        .navigationTitle("Animation Editor")
        .onAppear {
            loadData()
        }
        .onChange(of: animationId) { _ in
            loadData()
        }
    }
    
    func updateAnimationTitle(newValue: String) {
        if let _ = animation {
            animation?.metadata.title = newValue
        }
    }
    
    func updateAnimationNotes(newValue: String) {
        if let _ = animation {
            animation?.metadata.notes = newValue
        }
    }
    
    func loadData() {
        Task {
            
            if let idToFetch = animationId {
                let result = await client.getAnimation(animationId: idToFetch)
                
                switch(result) {
                case .success(let data):
                    logger.debug("success!")
                    self.animation = data
                    title = data.metadata.title
                    notes = data.metadata.notes
                case .failure(let error):
                    print("Error: \(String(describing: error.errorDescription))")
                    
                }
            }
            
            creature = Creature.mock()
        }
    }
}

// Thank you ChatGPT for this amazing little function
extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        return Binding<Value>(
            get: { self.wrappedValue },
            set: { newValue in
                self.wrappedValue = newValue
                handler(newValue)
            }
        )
    }
}

struct AnimationEditor_Previews: PreviewProvider {

    static var previews: some View {
        AnimationEditor(animationId: DataHelper.generateRandomData(byteCount: 12))
    }
}

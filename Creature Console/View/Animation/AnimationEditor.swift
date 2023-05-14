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
    
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    
    let logger = Logger(label: "Animtion Editor")
    
    @State private var title : String = ""
    @State private var notes : String = ""
    @State private var soundFile : String = ""
    
   
    var body: some View {
        VStack {
            Form {
                TextField("Title", text: $title.onChange(updateAnimationTitle))
                    .textFieldStyle(.roundedBorder)
                
                TextField("Sound File", text: $soundFile.onChange(updateSoundFile))
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notes", text: $notes.onChange(updateAnimationNotes))
                    .textFieldStyle(.roundedBorder)
                
                
            }
            .padding()
            
        
            AnimationWaveformEditor(animation: $animation)
            
            
        }
        .navigationTitle("Animation Editor")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                    Button(action: {
                        print("Toolbar button tapped!")
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
            }
            ToolbarItem(placement: .automatic) {
                    Button(action: {
                        print("Play button tapped!")
                    }) {
                        Image(systemName: "play")
                    }
            }
        }
        .onAppear {
            loadData()
        }
        .onChange(of: animationId) { _ in
            loadData()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Oooooh Shit"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Fuck"))
            )
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
    
    func updateSoundFile(newValue: String) {
        if let _ = animation {
            animation?.metadata.soundFile = newValue
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
                    soundFile = data.metadata.soundFile
                case .failure(let error):
                     
                    // If an error happens, pop up a warning
                    errorMessage = "Error: \(String(describing: error.errorDescription))"
                    showErrorAlert = true
                    logger.error(Logger.Message(stringLiteral: errorMessage))
                    
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
        AnimationEditor(animationId: DataHelper.generateRandomData(byteCount: 12),
                        animation: .mock())
    }
}

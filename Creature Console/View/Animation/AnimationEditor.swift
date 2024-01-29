
import SwiftUI
import OSLog


// This is the main animation editor for all of the Animations

struct AnimationEditor: View {
    
    var animationId: Data?
    
    @EnvironmentObject var client: CreatureServerClient
    @EnvironmentObject var appState : AppState
    @EnvironmentObject var eventLoop : EventLoop
    
    @State var creature : Creature
    @State var animation : Animation?
    
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditor")
    
    @State private var title : String = ""
    @State private var notes : String = ""
    @State private var soundFile : String = ""
    
    @State private var isSaving : Bool = false
    @State private var savingMessage : String = ""
   
    var body: some View {
        VStack {
            Form {
                
                TextField("Title", text: $title.onChange(updateAnimationTitle))
                    .textFieldStyle(.roundedBorder)
                
                TextField("Sound File", text: $soundFile.onChange(updateSoundFile))
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notes", text: $notes.onChange(updateAnimationNotes))
                    .textFieldStyle(.roundedBorder)
                
                SoundDataImport(animation: $animation)
                
            }
            .padding()
            
        
            AnimationWaveformEditor(animation: $animation, creature: $creature)
               
            
            
        }
        .navigationTitle("Animation Editor")
#if os(macOS)
        .navigationSubtitle(creature.name)
#endif
        .toolbar(id: "animationEditor") {
            ToolbarItem(id: "save", placement: .primaryAction) {
                    Button(action: {
                        saveAnimationToServer()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
            }
            ToolbarItem(id:"play", placement: .primaryAction) {
                    Button(action: {
                        playAnimation()
                    }) {
                        Image(systemName: "play.fill")
                    }
            }
            ToolbarItem(id: "re-record", placement: .secondaryAction) {
                NavigationLink(destination: RecordAnimation(
                    animation: animation,
                    creature: creature,
                    joystick: eventLoop.getActiveJoystick()
                    ), label: {
                        Label("Re-Record", systemImage: "repeat.circle")
                    })
            }
        }
        .onAppear {
            print("hi I appear")
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
        .overlay {
            if isSaving {
                Text(savingMessage)
                    .font(.title)
                    .padding()
                    .background(Color.green.opacity(0.4))
                    .cornerRadius(10)
            }
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
                    errorMessage = "Error: \(String(describing: error.localizedDescription))"
                    showErrorAlert = true
                    //logger.error(errorMessage)
                    
                }
            }
        }
    }
    
    func playAnimation() -> Result<String, AnimationError> {
        
        logger.info("play button pressed!")
      
        Task {
            if let a = animation {
                
                do {
                    try await client.playAnimationLocally(animation: a, creature: creature)
                } catch {
                    logger.error("Unable to play animation: \(error.localizedDescription)")
                }
            }
        }
        
        return .success("Queued up animation to play")
    }
    
    
    func saveAnimationToServer() {
        savingMessage = "Saving animation to server..."
        isSaving = true
        Task {
            if let a = animation {
                
                let result = await client.updateAnimation(animationToUpdate: a)
    
                switch(result) {
                case .success(let data):
                    savingMessage = data
                    logger.debug("success!")
                    
                case .failure(let error):
                    
                    // If an error happens, pop up a warning
                errorMessage = "Error: \(String(describing: error.localizedDescription))"
                    showErrorAlert = true
                    //logger.error(OSLogMessage(stringInterpolation: errorMessage))
                    
                }
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
                catch {}
                isSaving = false
            }

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
                        creature: .mock(),
                        animation: .mock()
                        )
        .environmentObject(EventLoop.mock())
        .environmentObject(CreatureServerClient.mock())
    }
}

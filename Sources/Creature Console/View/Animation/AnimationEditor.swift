
import SwiftUI
import OSLog
import Common


// This is the main animation editor for all of the Animations
struct AnimationEditor: View {
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationEditor")

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared

    let eventLoop = EventLoop.shared
    let creatureManager = CreatureManager.shared

    // We need a path to ourselves! The track recorder needs it so it knows how
    // to get back to us when it's done.
    @State var path = NavigationPath()

    @StateObject var appState = AppState.shared

    // The parent view will set this to true if we're about to make a _new_ animation
    @State var createNew: Bool = false

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    @State private var isSaving : Bool = false
    @State private var savingMessage : String = ""
   
    var body: some View {
        VStack {

            if appState.currentAnimation != nil {
                Form {
                    TextField("Title", text: binding(for: \.metadata.title))
                        .textFieldStyle(.roundedBorder)

                    TextField("Sound File", text: binding(for: \.metadata.soundFile))
                        .textFieldStyle(.roundedBorder)

                    TextField("Notes", text: binding(for: \.metadata.note))
                        .textFieldStyle(.roundedBorder)
                }
                .padding()

                TrackListingView()

                Spacer()

            }


        
            //AnimationWaveformEditor(animation: appState.currentAnimation, creature: creature)

        }
        .navigationTitle(createNew ? "Record New Animation" : "Animation Editor")
#if os(macOS)
        .navigationSubtitle("Active Universe: \(activeUniverse)")
#endif
        .toolbar(id: "animationEditor") {
            ToolbarItem(id: "save", placement: .secondaryAction) {
                    Button(action: {
                        saveAnimationToServer()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
            }
            ToolbarItem(id:"play", placement: .secondaryAction) {
                    Button(action: {
                        _ = playAnimation()
                    }) {
                        Image(systemName: "play.fill")
                    }
            }
            ToolbarItem(id: "newTrack", placement: .primaryAction) {

                NavigationLink(destination: RecordTrack(path: $path), label: {
                    Label("Add Track", systemImage: "plus")
                        .foregroundColor(.accentColor)
                    }
                )
            }
        }
        .onAppear {
            if createNew {
                logger.info("createNew is true, so I'm making a new Animation")
                self.prepareAnimation()
                createNew = false
            }
            else
            {
                print("hi I appear")
                loadData()
            }
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
        if let a = appState.currentAnimation {
            a.metadata.title = newValue
        }
    }
    
    func updateAnimationNotes(newValue: String) {
        if let a = appState.currentAnimation {
            a.metadata.note = newValue
        }
    }
    
    func updateSoundFile(newValue: String) {
        if let a = appState.currentAnimation {
            a.metadata.soundFile = newValue
        }
    }
    
    func loadData() {

    }
    
    func playAnimation() -> Result<String, AnimationError> {
        
        logger.info("play button pressed!")
      
//        Task {
//            if let a = animation {
//                
//                let result =  await creatureManager.playAnimationLocally(animation: a, universe: activeUniverse)
//                switch(result) {
//                case (.failure(let message)):
//                    logger.error("Unable to play animation: \(message))")
//                default:
//                    break
//                }
//            }
//        }
        
        return .success("Queued up animation to play")
    }
    
    
    private func binding<T>(for keyPath: ReferenceWritableKeyPath<Common.Animation, T>) -> Binding<T> {
        Binding(
            get: {
                appState.currentAnimation?[keyPath: keyPath] ?? "N/A" as! T
            },
            set: {
                if appState.currentAnimation != nil {
                    appState.currentAnimation?[keyPath: keyPath] = $0
                }
            }
        )
    }

    func saveAnimationToServer() {
        savingMessage = "Saving animation to server..."
        isSaving = true
//        Task {
//            if let a = animation {
//                
//                let result = await server.createAnimation(animation: a)
//
//                switch(result) {
//                case .success(let data):
//                    savingMessage = data
//                    logger.debug("success!")
//                    
//                case .failure(let error):
//                    
//                    // If an error happens, pop up a warning
//                errorMessage = "Error: \(String(describing: error.localizedDescription))"
//                    showErrorAlert = true
//                    //logger.error(OSLogMessage(stringInterpolation: errorMessage))
//                    
//                }
//                do {
//                    try await Task.sleep(nanoseconds: 2_000_000_000)
//                }
//                catch {}
//                isSaving = false
//            }
//
//        }
    }
    

    /**
     Create a new animation and get it ready to go
     */
    func prepareAnimation() {

        // TODO: Ask what do to if it exists, maybe?
        appState.currentAnimation = Common.Animation()
        logger.info("prepared a new Animation in the AppState")

    }


}



struct AnimationEditor_Previews: PreviewProvider {

    static var previews: some View {
        AnimationEditor(createNew: true)
    }
}

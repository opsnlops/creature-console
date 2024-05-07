
import SwiftUI
import OSLog

struct AnimationTable: View {

    let eventLoop = EventLoop.shared
    @ObservedObject var creature: Creature
    
    let server = CreatureServerClient.shared

    @State var animations : [AnimationMetadata]?

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationTable")
    
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var selection: AnimationMetadata?

    @State private var loadDataTask: Task<Void, Never>? = nil
        
    
    var body: some View {
        VStack {
            Text("Animations for \(creature.name)")
                .font(.title3)
            
            if let animations = animations {

                Table(animations, selection: $selection) {
                    TableColumn("Name") { a in
                        Text(a.title)
                    }
                    .width(min: 120, ideal: 250)
                    TableColumn("Frames") { a in
                        Text(a.numberOfFrames, format: .number)
                    }
                    .width(60)
                    TableColumn("Period") { a in
                        Text("\(a.millisecondsPerFrame)ms")
                    }
                    .width(55)
                    TableColumn("Audio") { a in
                        Text(a.soundFile)
                    }
                    TableColumn("Time (ms)") { a in
                        Text(a.milliseconds, format: .number)
                    }
                    .width(80)
                }
                .contextMenu(forSelectionType: AnimationIdentifier.self) { a in
                    if a.isEmpty {
                        NavigationLink(destination: RecordAnimation(
                            creature: creature,
                            joystick: eventLoop.getActiveJoystick()
                            ), label: {
                                Label("Record new Animation", systemImage: "record.circle")
                            })
                    } else {
                        
                        
                        Button {
                            print("play sound file selected")
                        } label: {
                            Label("Play Sound File", systemImage: "music.quarternote.3")
                        }
                        Button {
                            playAnimationLocally()
                        } label: {
                            Label("Play Locally", systemImage: "play.fill")
                        }
                        Button {
                            playAnimationOnServer()
                        } label: {
                            Label("Play on Server", systemImage: "play")
                        }
                         
                        NavigationLink(destination: AnimationEditor(
                            animationId: selection,
                            creature: creature), label: {
                                Label("Edit Animation", systemImage: "pencil")
                            })
                    }
                    
                    
                }
                
                Spacer()
                
                HStack {
                
                    Button {
                        playAnimationLocally()
                    } label: {
                        Label("Play Locally", systemImage: "play.fill")
                            .foregroundColor(.green)
                    }
                    .disabled(selection == nil)
                    
                    
                    Button {
                        playAnimationOnServer()
                    } label: {
                        Label("Play on Server", systemImage: "play")
                            .foregroundColor(.blue)
                    }
                    .disabled(selection == nil)
                    
                    
                    NavigationLink(destination: AnimationEditor(
                        animationId: selection,
                        creature: creature), label: {
                            Label("Edit", systemImage: "pencil")
                                .foregroundColor(.accentColor)
                        })
                    .disabled(selection == nil)
                    
                    
                }
                .padding()
                
            }
            else {
                ProgressView("Loading animations for \(creature.name)")
                    .padding()
            }
        }
        .onAppear {
            logger.debug("onAppear()")
            loadData()
        }
        .onDisappear {
            loadDataTask?.cancel()
        }
        .onChange(of: selection) {
            print("selection is now \(String(describing: selection))")
        }
        .onChange(of: creature) {
            logger.info("onChange() in AnimationTable")
            loadData()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Unable to load Animations"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Fiiiiiine"))
            )
        }
    }
    
    func playAnimationLocally() {
        
        logger.info("fetching animation \(String(describing: selection)) from server...")
        
        // Start a background task
        Task {
            
            if let animationId = selection {
                
                let animation = await server.getAnimation(animationId: animationId)

                switch animation {
                case .success(let a):
                    do {
                        try await server.playAnimationLocally(animation: a, creature: creature)
                    } catch {
                        logger.error("playAnimationLocally threw: \(error)")
                    }
                case .failure(let error):
                    logger.error("unable to play animation locally: \(error)")
                }
                
            }
            else {
                logger.warning("nothing selected in playAnimationLocally()?")
            }
        
        }
        
        logger.debug("play animation task fired off")
        
    }
    
    func playAnimationOnServer() {
        
        logger.info("attempting to play an animation on the server")
        
        if let s = selection {
            
            // Fire off a background task to talk to the server
            Task {
                let result = await server.playAnimationOnServer(animationId: s, creatureId: creature.id)

                switch result {
                case .success(let data):
                    logger.info("Server said: \(data)")
                case .failure(let error):
                    logger.warning("Unable to play animation! Server said: \(error)")
                }
            }
            logger.debug("task to talk to the server fired off!")
        }
        else {
            logger.warning("nothing selected in playAnimationOnServer()?")
        }
        
    }
    
    
    func loadData() {
        
        loadDataTask?.cancel()
                
        loadDataTask = Task {
            // Go load the animations
            let pValue = creature.type.protobufValue
            let result = await client.listAnimations(creatureType: pValue)
            logger.debug("Loaded animations for \(creature.name)")
            
            switch(result) {
            case .success(let data):
                logger.debug("success!")
                self.animationIds = data
            case .failure(let error):
                alertMessage = "Error: \(String(describing: error.localizedDescription))"
                logger.warning("Unable to load the animations for \(creature.name): \(String(describing: error.localizedDescription))")
                showErrorAlert = true
            }
        }
    }
}

struct AnimationTable_Previews: PreviewProvider {
    static var previews: some View {
        AnimationTable(creature: .mock(),
                       animations: [.mock(), .mock(), .mock()])
    }
}

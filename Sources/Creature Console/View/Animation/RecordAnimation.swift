
import SwiftUI
import OSLog
import AVFoundation
import Common


struct RecordAnimation: View {
    
    let appState = AppState.shared
    let audioManager = AudioManager.shared
    let eventLoop = EventLoop.shared
    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    @ObservedObject var joystickManager = JoystickManager.shared

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1
    @AppStorage("eventLoopMillisecondsPerFrame") var millisecondsPerFrame = 20

    @State var animation : Common.Animation?
    @State private var errorMessage = ""
    @State private var showErrorMessage = false
    
    @State var creature : Creature


    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RecordAnimation")
    
    @State var title = ""
    @State var notes = ""
    @State var soundFile = ""
    @State var multitrackAudio: Bool = false
    @State var lastUpdated: Date = Date()

    @State private var streamingTask: Task<Void, Never>? = nil
    @State private var recordingTask: Task<Void, Never>? = nil

    @State private var isSaving : Bool = false
    @State private var savingMessage : String = ""
        
    
    var body: some View {
        VStack {
            
            Form {
                Section(header: Text("Title")) {
                    TextField("", text: $title)
                }
                Section(header: Text("Sound File")) {
                    TextField("", text: $soundFile)
                }
                Section(header: Text("Notes")) {
                    TextField("", text: $notes)
                }
                Section(header: Text("Millisecond Per Frame")) {
                    TextField("", value: $millisecondsPerFrame, format: .number)
                        .disabled(true)
                }
            }
                
            HStack {
                Text("Press")
                    .font(.title)
                Image(systemName: joystickManager.getActiveJoystick().getXButtonSymbol())
                    .font(.title)
                if(appState.currentActivity == .recording) {
                    Text("to stop")
                        .font(.title)
                }
                else {
                    Text("to start")
                        .font(.title)
                }
            }
           
            // Show either nothing, the joystick debugger, or a waveform if we have one
            if(appState.currentActivity == .preparingToRecord || appState.currentActivity == .recording) {
                JoystickDebugView()
            } else {
                if let animation = animation {
                    VStack {
                        AnimationWaveformEditor(animation: $animation, creature: $creature)
                        HStack {
                            Text("Frames: \(animation.metadata.numberOfFrames)")

                            // Allow it to be played before it's saved
                            Button( action: {
                                playAnimationLocally()
                            }, label: {
                                Label("Play Animation", systemImage: "play.fill")
                                    .foregroundColor(.green)
                            })
                            
                            // Discard this attempt and try again
                            Button( action: {
                                self.animation = nil
                            }, label: {
                                Label("Record Again", systemImage: "repeat.circle.fill")
                                    .foregroundColor(.accentColor)
                            })
                            .disabled(self.animation == nil)
                            
                            
                            // If there's a title, allow saving to the database
                            Button(action: {
                                saveToServer()
                            }, label: {
                                Label("Save to Server", systemImage: "square.and.arrow.down.fill")
                                    .foregroundColor(title.isEmpty ? .secondary : .red)
                            })
                            .disabled(title.isEmpty)
                                      
                        }
                    }
                    .padding()
                }
                else {
                    Spacer()
                }
            }

        }
        .navigationTitle("Record Animation")
#if os(macOS)
        .navigationSubtitle("Name: \(creature.name), Channel Offset: \(creature.channelOffset)")
#endif
        .onDisappear{

            
            // Clean up our tasks if they're still running
            streamingTask?.cancel()
            recordingTask?.cancel()
            
        }
        .onChange(of: joystickManager.xButtonPressed) {            if joystickManager.xButtonPressed {

                switch(appState.currentActivity) {
                case .idle:
                    startRecording()
                case .recording:
                    stopRecording()
                case .preparingToRecord:
                    stopRecording()
                default:
                    appState.currentActivity = .idle
                }
            }
        }
//        .onReceive(joystick.changesPublisher) {
//            self.values = joystick.getValues()
//            self.aButtonPressed = joystick.aButtonPressed
//            self.bButtonPressed = joystick.bButtonPressed
//            self.xButtonPressed = joystick.xButtonPressed
//            self.yButtonPressed = joystick.yButtonPressed
//        }
        .alert(isPresented: $showErrorMessage) {
            Alert(
                title: Text("Server Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
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
    
    func playWarningTone() {
        
        logger.info("attempting to play the warning tone")
        
        let result = audioManager.playBundledSound(name: "recordingCountdownSound", extension: "flac" )
        
        switch (result) {
        case .success(let data):
            logger.info("\(data.description)")
        case .failure(let data):
            logger.warning("\(data.localizedDescription)")
        }
        
    }
    
    func playAnimationLocally() {
        
        if let a = animation {
            Task {

                let result = await creatureManager.playAnimationLocally(animation: a, universe: activeUniverse)
                switch(result) {
                case .failure(let error):
                    logger.error("Unable to play animation locally: \(error.localizedDescription)")
                default:
                    break
                }
            }
        }
        else {
            logger.warning("attempted to play a nil animation?")
        }
        
    }
    
    func startRecording() {
       
        // Start streaming to the creature
        streamingTask = Task {

            await _ = creatureManager.startStreamingToCreature(creatureId: creature.id)



        }
        
        // Work in the background
        recordingTask = Task {
            
            appState.currentActivity = .preparingToRecord
            
            
            let metadata = AnimationMetadata(
                // The animationID will be re-written by the server. This is just a placeholder.
                id: DataHelper.generateRandomId(),
                title: title,
                lastUpdated: lastUpdated,
                millisecondsPerFrame: UInt32(eventLoop.millisecondPerFrame),
                note: notes,
                soundFile: soundFile,
                numberOfFrames: 0,
                multitrackAudio: multitrackAudio)

            
            do {
                playWarningTone()
                try await Task.sleep(nanoseconds: UInt64(3.8 * 1_000_000_000))
            } catch {
                logger.error("couldn't sleep?")
            }
            
            appState.currentActivity = .recording
            
            
            logger.info("asking new recording to start")
            eventLoop.recordNewAnimation(metadata: metadata)
            
        }
        
    }
    
    func stopRecording() {
        eventLoop.stopRecording()
        recordingTask?.cancel()
        logger.info("asked recording to stop")
        
        // Stop streaming
        //server.stopSignalReceived = true
        streamingTask?.cancel()
        
        appState.currentActivity = .idle
        
        // Point our stuff at it
        animation = eventLoop.animation
    }
    
    func saveToServer() {
        savingMessage = "Saving animation to server..."
        isSaving = true
        Task {
            if let a = eventLoop.animation {
                
                a.metadata.title = title
                a.metadata.note = notes
                a.metadata.soundFile = soundFile
                a.metadata.multitrackAudio = multitrackAudio
                a.metadata.lastUpdated = Date()     // Right now

                let result = await server.createAnimation(animation: a)
                switch(result) {
                case .success(let hooray):
                    savingMessage = hooray
                    logger.info("Server said: \(hooray)")
                case .failure(let shame):
                    errorMessage = shame.localizedDescription
                }
            }
            
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            catch {}
            isSaving = false
        }
    }
}


struct RecordAnimation_Previews: PreviewProvider {
    static var previews: some View {
        RecordAnimation(creature: .mock())
        .environmentObject(EventLoop.mock())
        .environmentObject(AppState.mock())
    }
}

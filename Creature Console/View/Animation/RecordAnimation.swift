
import SwiftUI
import OSLog
import AVFoundation

struct RecordAnimation: View {
    
    @EnvironmentObject var appState : AppState
    @EnvironmentObject var audioManager : AudioManager
    @EnvironmentObject var eventLoop : EventLoop
    @EnvironmentObject var client: CreatureServerClient
    
    @State var animation : Animation? 
    @State private var errorMessage = ""
    @State private var showErrorMessage = false
    
    @State var creature : Creature
    var joystick : Joystick
    @State private var values: [UInt8] = []
    @State private var xButtonPressed = false
    @State private var yButtonPressed = false
    @State private var aButtonPressed = false
    @State private var bButtonPressed = false
    
    
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "RecordAnimation")
    
    @State var title = ""
    @State var notes = ""
    @State var soundFile = ""
    
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
                    TextField("", value: $eventLoop.millisecondPerFrame, format: .number)
                        .disabled(true)
                }
                Section(header: Text("Number of Motors")) {
                    TextField("", value: $creature.numberOfMotors, format: .number)
                        .disabled(true)
                }
            }
                
            HStack {
                Text("Press")
                    .font(.title)
                Image(systemName: eventLoop.sixAxisJoystick.controller?.extendedGamepad?.buttonX.sfSymbolsName ?? "x.circle")
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
                JoystickDebugView(joystick: joystick)
            } else {
                if let animation = animation {
                    VStack {
                        AnimationWaveformEditor(animation: $animation, creature: $creature)
                        HStack {
                            Text("Frames: \(animation.numberOfFrames)")
                            
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
        .navigationSubtitle("Name: \(creature.name), Type: \(creature.type.description)")
#endif
        .onDisappear{
            if let j = joystick as? SixAxisJoystick {
                j.removeVirtualJoystickIfNeeded()
            }
            
            // Clean up our tasks if they're still running
            streamingTask?.cancel()
            recordingTask?.cancel()
            
        }
        .onAppear {
        
            // Delay setting these values until after the init()'er is done
            values = joystick.getValues()
            xButtonPressed = joystick.xButtonPressed
            yButtonPressed = joystick.yButtonPressed
            aButtonPressed = joystick.aButtonPressed
            bButtonPressed = joystick.bButtonPressed
            
            if let j = joystick as? SixAxisJoystick {
                j.showVirtualJoystickIfNeeded()
            }
                    
        }
        .onChange(of: xButtonPressed) {            if xButtonPressed {
                
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
        .onReceive(joystick.changesPublisher) {
            self.values = joystick.getValues()
            self.aButtonPressed = joystick.aButtonPressed
            self.bButtonPressed = joystick.bButtonPressed
            self.xButtonPressed = joystick.xButtonPressed
            self.yButtonPressed = joystick.yButtonPressed
        }
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
                do {
                    try await client.playAnimationLocally(animation: a, creature: creature)
                } catch {
                    logger.error("error playing animation: \(error)")
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
            do {
                try await client.streamJoystick(joystick: joystick, creature: creature)
            }
            catch {
                logger.error("Unable to stream: \(error.localizedDescription)")
            }
        }
        
        // Work in the background
        recordingTask = Task {
            
            appState.currentActivity = .preparingToRecord
            
            
            let metadata = Animation.Metadata(
                // The animationID will be re-written by the server. This is just a placeholder.
                animationId: DataHelper.generateRandomData(byteCount: 12),
                title: title,
                millisecondsPerFrame: Int32(eventLoop.millisecondPerFrame),
                creatureType: creature.type.protobufValue,
                numberOfMotors: Int32(creature.numberOfMotors),
                notes: notes,
                soundFile: soundFile)
            
            
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
        client.stopSignalReceived = true
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
                a.metadata.notes = notes
                a.metadata.soundFile = soundFile
                
                let result = await client.createAnimation(animation: a)
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
        RecordAnimation(creature: .mock(), joystick: SixAxisJoystick.mock())
        .environmentObject(EventLoop.mock())
        .environmentObject(AppState.mock())
    }
}

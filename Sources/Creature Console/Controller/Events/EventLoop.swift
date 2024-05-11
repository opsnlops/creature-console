
import Foundation
import OSLog
import SwiftUI
import Common


/**
 This EventLoop runs on a background thread!
 
 This means that updates to the UI need to be dispatched to the main thread. This can be done like this:
 
 DispatchQueue.main.async {
    doAThing();
 }
 
 */
class EventLoop : ObservableObject {
    
    // Make a singleton out of this
    static let shared = EventLoop()

    private var timer: DispatchSourceTimer?
    private(set) var number_of_frames : Int64 = 0
    
    // Use the other Singletons
    let appState = AppState.shared
    let audioManager  = AudioManager.shared
    let creatureManager = CreatureManager.shared

    @Published var frameIdleTime: Double
    
    /**
     These are populated from syncSettings()
     */
    var millisecondPerFrame : Int
    var logSpareTimeFrameInterval : Int
    var useOurJoystick: Bool = false
    var logSpareTime: Bool = false
        
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "EventLoop")
    private let numberFormatter = NumberFormatter()
    
    // Behold, the two genders
    var sixAxisJoystick: SixAxisJoystick
#if os(macOS)
    var acwJoystick: AprilsCreatureWorkshopJoystick
#endif
    

    // If we've got an animation loaded, keep track of it
    var animation : Common.Animation?
    var isRecording = false

    @AppStorage("audioFilePath") var audioFilePath: String = ""
    
    /**
     Sync settings that may have changed from the user preferences
     */
    func syncSettings() {
        self.millisecondPerFrame = UserDefaults.standard.integer(forKey: "eventLoopMillisecondsPerFrame")
        self.logSpareTimeFrameInterval = UserDefaults.standard.integer(forKey: "logSpareTimeFrameInterval")
        self.logSpareTime = UserDefaults.standard.bool(forKey: "logSpareTime")
        self.useOurJoystick = UserDefaults.standard.bool(forKey: "useOurJoystick")
    }
    
    /**
     Start up all of the things
     */
    init() {
        self.sixAxisJoystick = SixAxisJoystick()
        #if os(macOS)
        self.acwJoystick = AprilsCreatureWorkshopJoystick(vendorID: 0x0666, productID: 0x0001)
        #endif
        self.millisecondPerFrame = UserDefaults.standard.integer(forKey: "eventLoopMillisecondsPerFrame")
        self.logSpareTimeFrameInterval = UserDefaults.standard.integer(forKey: "logSpareTimeFrameInterval")
        self.useOurJoystick = UserDefaults.standard.bool(forKey: "useOurJoystick")
        self.logSpareTime = UserDefaults.standard.bool(forKey: "logSpareTime")
        self.frameIdleTime = 100.0
        
        // Configure the number formatter
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 2
  
        syncSettings()
        startTimer()
        
        logger.info("event loop started")
    }

    deinit {
        stopTimer()
        logger.info("event loop stopped")
    }
    
    
    func recordNewAnimation(metadata: AnimationMetadata) {
        animation = Animation(id: DataHelper.generateRandomId(),
                              metadata: metadata,
                              frameData: [])

        // Set our state to recording
        DispatchQueue.main.async {
            self.appState.currentActivity = .recording
        }
        
        // If it has a sound file attached, let's play it
        if !metadata.soundFile.isEmpty {
            
            // See if it's a valid url
            if let url = URL(string: audioFilePath + metadata.soundFile) {
                
                do {
                    logger.info("audiofile URL is \(url)")
                    Task {
                        await audioManager.play(url: url)
                    }
                }
            }
            else {
                logger.warning("audioFile URL doesn't exist: \(self.audioFilePath + metadata.soundFile)")
            }
        } else {
            logger.info("no audio file, skipping playback")
        }
        
        // Tell the system to start recording
        isRecording = true
    }
    
    func stopRecording() {
        isRecording = false
        DispatchQueue.main.async {
            self.appState.currentActivity = .idle
        }
    }
    
    /**
     Main Event Loop
     */
    private func update() {
        
        // Keep metrics on how long the the loop takes
        let startTime = DispatchTime.now()
        
        
        // Update our metrics
        number_of_frames += 1
        
        // Which joystick should we use for this pass?
        let joystick = getActiveJoystick()
        

        // If we have a joystick, poll it
        if (joystick.isConnected()) {
            joystick.poll()
        }
       
        // If we are recording, grab the data now
        if( isRecording ) {
            Task {
                await creatureManager.grabFrame()
            }
        }
        
        
        // Update metrics
        let endTime = DispatchTime.now()
        let elapsedTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
 

        // If it's time to print out a logging message with our info, do it now
        
        if(self.logSpareTime && number_of_frames % Int64(logSpareTimeFrameInterval) == 1) {
            let elapsedTimeInMilliseconds = Double(elapsedTime) / 1_000_000.0
            let frameTimeInNanoseconds = Double(millisecondPerFrame) * 1_000_000.0
            let localFrameIdleTime = (1 - (Double(elapsedTime) / frameTimeInNanoseconds)) * 100.0
            
            let elapsedTimeString = numberFormatter.string(from: NSNumber(value: elapsedTimeInMilliseconds)) ?? "0.00"
            let idleTimeString = numberFormatter.string(from: NSNumber(value: localFrameIdleTime)) ?? "0.00"
                        
            logger.trace("Frame time: \(elapsedTimeString)ms (\(idleTimeString)% Idle)")
            
            // Update this metric for anyone watching
            DispatchQueue.main.async {
                self.frameIdleTime = localFrameIdleTime
            }
            
        }
        
        /**
         Re-sync our settings
         */
        syncSettings()
        
    }
    
    /**
     Return whatever the joystick is we should use for an operation
     */
    func getActiveJoystick() -> Joystick {
        
        var joystick: Joystick
        
        /**
         On macOS we could our joystick, or the system one.
         */
        #if os(macOS)
        if acwJoystick.connected && useOurJoystick {
            joystick = acwJoystick
        }
        else {
            joystick = sixAxisJoystick
        }
        #endif
        
        /**
         On iOS we don't have a choice. IOKit does not exist there.
         */
        #if os(iOS)
        joystick = sixAxisJoystick
        #endif
        
        return joystick
    }

    private func startTimer() {
        logger.info("Starting event loop at \(self.millisecondPerFrame)ms per frame")

        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer?.setEventHandler { [weak self] in
            self?.update()
        }
        timer?.schedule(deadline: .now(), repeating: .milliseconds(millisecondPerFrame), leeway: .nanoseconds(0))
        timer?.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
    
}

extension EventLoop {
    static func mock() -> EventLoop {
        let mockEventLoop = EventLoop()
        mockEventLoop.millisecondPerFrame = 50
        mockEventLoop.logSpareTimeFrameInterval = 100
        mockEventLoop.frameIdleTime = 100.0

        // Configure the mock joystick if needed
        mockEventLoop.sixAxisJoystick = .mock()
#if os(macOS)
        mockEventLoop.acwJoystick = .mock()
#endif

        // Configure the mock animation if needed
        mockEventLoop.animation = .mock()

        return mockEventLoop
    }
}

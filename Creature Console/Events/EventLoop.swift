
import Foundation
import OSLog
import SwiftUI

/**
 This EventLoop runs on a background thread!
 
 This means that updates to the UI need to be dispatched to the main thread. This can be done like this:
 
 DispatchQueue.main.async {
    doAThing();
 }
 
 */
class EventLoop : ObservableObject {
    private var timer: DispatchSourceTimer?
    @Published var millisecondPerFrame : Int
    @Published var logSpareTimeFrameInterval : Int
    @Published var frameIdleTime: Double
    private(set) var number_of_frames : Int64 = 0
    @AppStorage("useOurJoystick") private var useOurJoystick: Bool = true
        
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "EventLoop")
    private let numberFormatter = NumberFormatter()
    
    // Behold, the two genders
    var sixAxisJoystick: SixAxisJoystick
#if os(macOS)
    var acwJoystick: AprilsCreatureWorkshopJoystick
#endif
    
    var appState : AppState

    
    // If we've got an animation loaded, keep track of it
    var animation : Animation?
    var isRecording = false
    
    var audioManager : AudioManager?
    @AppStorage("audioFilePath") var audioFilePath: String = ""
    
    /**
     Start up all of the things
     */
    init(appState: AppState) {
        self.appState = appState
        self.sixAxisJoystick = SixAxisJoystick(appState: appState)
        #if os(macOS)
        self.acwJoystick = AprilsCreatureWorkshopJoystick(appState: appState, vendorID: 0x0666, productID: 0x0001)
        #endif
        self.millisecondPerFrame = UserDefaults.standard.integer(forKey: "eventLoopMillisecondsPerFrame")
        self.logSpareTimeFrameInterval = UserDefaults.standard.integer(forKey: "logSpareTimeFrameInterval")
        self.frameIdleTime = 100.0
        
        // Configure the number formatter
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 2
  
        startTimer()
        logger.info("event loop started")
    }

    deinit {
        stopTimer()
        logger.info("event loop stopped")
    }
    
    
    func recordNewAnimation(metadata: Animation.Metadata) {
        animation = Animation(id: DataHelper.generateRandomData(byteCount: 24),
                              metadata: metadata,
                              frames: [])
        
        // Set our state to recording
        DispatchQueue.main.async {
            self.appState.currentActivity = .recording
        }
        
        // If it has a sound file attached, let's play it
        if !metadata.soundFile.isEmpty {
            
            // See if it's a valid url
            if let url = URL(string: audioFilePath + metadata.soundFile) {
                
                logger.info("audiofile URL is \(url)")
                _ = audioManager?.play(url: url)
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
        var joystick = getActiveJoystick()
        

        // If we have a joystick, poll it
        if (joystick.isConnected()) {
            joystick.poll()
        }
       
        // If we are recording, grab the data now
        if( isRecording ) {
            animation?.addFrame(frames: joystick.getValues())
        }
        
        
        // Update metrics
        let endTime = DispatchTime.now()
        let elapsedTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        
        
        // If it's time to print out a logging message with our info, do it now
        if(number_of_frames % Int64(logSpareTimeFrameInterval) == 1) {
            let elapsedTimeInMilliseconds = Double(elapsedTime) / 1_000_000.0
            let frameTimeInNanoseconds = Double(millisecondPerFrame) * 1_000_000.0
            let localFrameIdleTime = (1 - (Double(elapsedTime) / frameTimeInNanoseconds)) * 100.0
            
            let elapsedTimeString = numberFormatter.string(from: NSNumber(value: elapsedTimeInMilliseconds)) ?? "0.00"
            let idleTimeString = numberFormatter.string(from: NSNumber(value: localFrameIdleTime)) ?? "0.00"
                        
            logger.debug("Frame time: \(elapsedTimeString)ms (\(idleTimeString)% Idle)")
            
            // Update this metric for anyone watching
            DispatchQueue.main.async {
                self.frameIdleTime = localFrameIdleTime
            }
            
        }
        
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
        let mockEventLoop = EventLoop(appState: .mock())
        mockEventLoop.millisecondPerFrame = 50
        mockEventLoop.logSpareTimeFrameInterval = 100
        mockEventLoop.frameIdleTime = 100.0

        // Configure the mock joystick if needed
        mockEventLoop.sixAxisJoystick = .mock()
        mockEventLoop.acwJoystick = .mock(appState: .mock())

        // Configure the mock animation if needed
        mockEventLoop.animation = .mock()

        return mockEventLoop
    }
}

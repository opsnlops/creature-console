//
//  EventLoop.swift
//  Creature Console
//
//  Created by April White on 4/16/23.
//

import Foundation
import Logging

/**
 This EventLoop runs on a background thread!
 
 This means that updates to the UI need to be dispatched to the main thread. This can be done like this:
 
 DispatchQueue.main.async {
    doAThing();
 }
 
 */
class EventLoop : ObservableObject {
    private var timer: DispatchSourceTimer?
    private let timerInterval: TimeInterval
    private(set) var framesPerSecond : Double
    private(set) var number_of_frames : Int64 = 0
    
    private let logger = Logger(label: "Event Loop")
    
    var joystick0 : SixAxisJoystick
    
    
    // If we've got an animation loaded, keep track of it
    var animation : Animation?
    var isRecording = false
    
    
    
    func recordNewAnimation(metadata: Animation.Metadata) {
        animation = Animation(id: DataHelper.generateRandomData(byteCount: 24),
                              metadata: metadata,
                              frames: [])
        isRecording = true
    }
    
    func stopRecording() {
        isRecording = false
    }
    
    /**
     Main Event Loop
     */
    private func update() {
        
        // Keep metrics on how long the the loop takes
        let startTime = DispatchTime.now()
        
        
        // Update our metrics
        number_of_frames += 1
        
        // If we have a joystick, poll it
        if (joystick0.controller != nil) {
            joystick0.poll()
        }
       
        // If we are recording, grab the data now
        if( isRecording ) {
            animation?.addFrame(frames: joystick0.axisValues)
        }
        
        // Update metrics
        let endTime = DispatchTime.now()
        let elapsedTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let elapsedTimeInSeconds = Double(elapsedTime) / 1_000_000.0
        
        if(number_of_frames % 1000 == 1) {
            logger.info("Frame time: \(elapsedTimeInSeconds)ms (\((1 - (elapsedTimeInSeconds / (timerInterval * 1000))) * 100.0)% Idle)")
        }
        
    }
    
    
    init() {
            self.joystick0 = SixAxisJoystick()
            framesPerSecond = UserDefaults.standard.double(forKey: "eventLoopFramesPerSecond")
            timerInterval = 1.0 / framesPerSecond

            startTimer()
            logger.info("event loop started")
        }

        deinit {
            stopTimer()
            logger.info("event loop stopped")
        }

        private func startTimer() {
            logger.info("Starting event loop at \(framesPerSecond) FPS (\(timerInterval * 1000)ms interval)")

            timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer?.setEventHandler { [weak self] in
                self?.update()
            }
            timer?.schedule(deadline: .now(), repeating: timerInterval, leeway: .nanoseconds(0))
            timer?.resume()
        }

        private func stopTimer() {
            timer?.cancel()
            timer = nil
        }
    
}

//
//  EventLoop.swift
//  Creature Console
//
//  Created by April White on 4/16/23.
//

import Foundation
import Logging




class EventLoop : ObservableObject {
    private var timer: Timer?
    private let timerInterval = 1.0 / 40.0 // TODO: Make this configurable
    private(set) var number_of_frames : Int64 = 0
    
    private let logger = Logger(label: "Event Loop")
    
    var joystick0 : SixAxisJoystick
    
    
    private func update() {
        
        // Update our metrics
        number_of_frames += 1
        
        
        // If we have a joystick, poll it
        if (joystick0.controller != nil) {
            joystick0.poll()
        }
       
    }
    
    
    init() {
        
        self.joystick0 = SixAxisJoystick()
        
        startTimer()
        logger.info("event loop started");
     }
     
     deinit {
         stopTimer()
         logger.info("event loop stopped");
     }
     
     private func startTimer() {
         timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
             self?.update()
         }
     }
     
     private func stopTimer() {
         timer?.invalidate()
         timer = nil
     }
     
    
    
}

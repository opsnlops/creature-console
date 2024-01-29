//
//  RealTimeControl.swift
//  Creature Console
//
//  Created by April White on 4/11/23.
//

import Foundation
import SwiftUI
import OSLog
import GRPC
import GameController


extension CreatureServerClient {
       
    func streamJoystick(joystick: SixAxisJoystick, creature: Creature) async throws {
        
        logger.info("request to stream to \(creature.name)")
        
        let streamFrames = server?.makeStreamFramesCall()
        
                
        var frame = Server_Frame()
        frame.creatureName = creature.name
        frame.channelOffset = creature.channelOffset
        frame.numberOfMotors = creature.numberOfMotors
        frame.universe = creature.universe
        
        var counter = UInt32(0)
        stopSignalReceived = false
        
        do {
            while !stopSignalReceived {
                
                counter += 1
                
                logger.debug("Streaming frame \(counter)")
                var frameData = Data()
                frameData.append(joystick.axises[0].value)
                frameData.append(joystick.axises[1].value)
                frameData.append(joystick.axises[2].value)
                frameData.append(joystick.axises[3].value)
                frameData.append(joystick.axises[4].value)
                frameData.append(joystick.axises[5].value)
                
                frame.frame = frameData
                
                try await streamFrames?.requestStream.send(frame)
                
                try await Task.sleep(nanoseconds: 20000000)
                
            }
        }
            
        streamFrames?.requestStream.finish()
        let summary = try await streamFrames?.response
        
        logger.info("Server processed \(summary?.framesProcessed ?? 666666666) frames")
  
            
    }
    
    
}

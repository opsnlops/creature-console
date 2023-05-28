//
//  RealTimeControl.swift
//  Creature Console
//
//  Created by April White on 4/11/23.
//

import Foundation
import SwiftUI
import Logging
import GRPC
import GameController


struct RealTimeControl: View {
    
    @ObservedObject var joystick : SixAxisJoystick
    @EnvironmentObject var client: CreatureServerClient
    var creature: Creature
    
    init(joystick: SixAxisJoystick, creature: Creature)
    {
        self.joystick = joystick
        self.creature = creature
    }
    
    
    var body: some View {
        VStack {
           Button("Start Streaming") {
               Task {
                   try await client.streamJoystick(joystick: joystick, creature: creature)
               }
           }

            Button("Stop Streaming") {
                client.stopSignalReceived = true
            }
       }
        .onDisappear{
            
            // Just in case I forget to turn off the streaming when I leave this view
            client.stopSignalReceived = true
            self.joystick.removeVirtualJoystickIfNeeded()
        }
        .onAppear {
            self.joystick.showVirtualJoystickIfNeeded()
        }
    }
        
}


extension CreatureServerClient {
    
    
    func streamJoystick(joystick: SixAxisJoystick, creature: Creature) async throws {
        
        logger.info("request to stream to \(creature.name)")
        
        joystick.currentActivity = .streaming
        
        let streamFrames = server?.makeStreamFramesCall()
        
        
        var frame = Server_Frame()
        frame.creatureName = creature.name
        frame.dmxOffset = creature.dmxBase
        frame.numberOfMotors = creature.numberOfMotors
        frame.sacnIp = creature.sacnIP
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
        
        joystick.currentActivity = .idle
            
    }
    
    
}


import Foundation
import SwiftUI
import OSLog
import GRPC
import GameController


extension CreatureServerClient {
       
    func streamJoystick(joystick: Joystick, creature: Creature, universe: UInt32) async throws {
        
        logger.info("request to stream to \(creature.name)")
        
        let streamFrames = server?.makeStreamFramesCall()
                        
        var frame = StreamFrameData(ceatureId: creature.id, universe: universe)

        var counter = UInt32(0)
        stopSignalReceived = false
        
        do {
            while !stopSignalReceived {
                
                counter += 1
                
                logger.debug("Streaming frame \(counter)")
                var frameData = Data()
                frameData.append(contentsOf: joystick.getValues())
                frame.data = frameData
                
                try await streamFrames?.requestStream.send(frame.toServerStreamFrameData())
                
                try await Task.sleep(nanoseconds: 20000000)
                
            }
        }
            
        streamFrames?.requestStream.finish()
        let summary = try await streamFrames?.response
        
        logger.info("Server processed \(summary?.framesProcessed ?? 666666666) frames")
  
            
    }
    
    
}

//
//  PlayAnimation.swift
//  Creature Console
//
//  Created by April White on 6/9/23.
//

import Foundation
import SwiftUI
import Logging
import GRPC


extension CreatureServerClient {
    
    
    /**
     Play an animation locally
     */
    func playAnimation(animation: Animation, creature: Creature) async throws -> Result<String, AnimationError> {
                
        // Make sure we're idle first
        guard appState!.currentActivity == .idle else {
            logger.warning("unable to play animation while not in \(AppState.Activity.idle.description) state")
            return .failure(.invalidState("🚫 Unable to play animation while not in the \(AppState.Activity.idle.description) state"))
        }
        
        // Make it clear we're now playing something
        DispatchQueue.main.async {
            self.appState!.currentActivity = .playingAnimation
        }
        
        logger.info("playing animation \(animation.metadata.title) on \(creature.name) (\(creature.sacnIP))")
        
       
        let streamFrames = server?.makeStreamFramesCall()
        
        // Set up the frame data that doesn't change
        var animationPlayingFrame = Server_Frame()
        animationPlayingFrame.creatureName = creature.name
        animationPlayingFrame.dmxOffset = creature.dmxBase
        animationPlayingFrame.numberOfMotors = creature.numberOfMotors
        animationPlayingFrame.sacnIp = creature.sacnIP
        animationPlayingFrame.universe = creature.universe
        
        // If it has a sound file attached, let's play it
        if !animation.metadata.soundFile.isEmpty {
            
            // See if it's a valid url
            if let url = URL(string: audioFilePath + animation.metadata.soundFile) {
                
                logger.info("audiofile URL is \(url)")
                
                var audioResult = audioManager?.play(url: url)
            }
        }
        
        
        var counter = 0
        isPlayingAnimation = true
        repeat {
             let startTime = DispatchTime.now()
                
             logger.trace("Playing frame \(counter)")
                var frameData = Data()
                
             animation.frames[counter].motorBytes.forEach { motor in
                    frameData.append(motor)
                }
                
            animationPlayingFrame.frame = frameData
            
            try await streamFrames?.requestStream.send(animationPlayingFrame)
            counter += 1
             
             // Sleep for the exact number of nanoseconds we need
             let endTime = DispatchTime.now()
             let elapsedTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
             try await Task.sleep(nanoseconds: UInt64((animation.metadata.millisecondsPerFrame * 1_000_000)) - elapsedTime )
                
            
        } while counter < animation.numberOfFrames && !emergencyStop
            
        streamFrames?.requestStream.finish()
        isPlayingAnimation = false
        
        // Resume being idle
        DispatchQueue.main.async {
            self.appState!.currentActivity = .idle
        }
        
        let summary = try await streamFrames?.response
        
        logger.info("Server played \(summary?.framesProcessed ?? 666666666) frames")
        return .success("Server played \(summary?.framesProcessed ?? 666666666) frames")
    }
}

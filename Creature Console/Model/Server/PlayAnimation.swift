//
//  PlayAnimation.swift
//  Creature Console
//
//  Created by April White on 6/9/23.
//

import Foundation
import SwiftUI
import OSLog
import GRPC


extension CreatureServerClient {
    
    
    /**
     Play an animation locally
     */
    func playAnimationLocally(animation: Animation, creature: Creature) async throws -> Result<String, AnimationError> {
                
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
                
                let audioResult = audioManager?.play(url: url)
                switch audioResult {
                    case .success(let data):
                        logger.info("\(data)")
                    case .failure(let data):
                        logger.error("Error playing audio: \(data)")
                    case .none:
                        logger.error("None error, left beef")
                }
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
             try await Task.sleep(nanoseconds: UInt64((animation.metadata.millisecondsPerFrame * 1_000_000)) - elapsedTime)
                
            
        } while counter < animation.numberOfFrames && !emergencyStop
            
        streamFrames?.requestStream.finish()
        isPlayingAnimation = false
        
        // Resume being idle
        DispatchQueue.main.async {
            self.appState!.currentActivity = .idle
        }
        
        let summary = try await streamFrames?.response
        
        logger.info("Server streamed \(summary?.framesProcessed ?? 666666666) frames")
        return .success("Server streamed \(summary?.framesProcessed ?? 666666666) frames")
    }
    
    
    /**
     Schedule playing an aimation on the server we're currently connected to
     */
    func playAnimationOnServer(animationId: Data, creatureId: Data) async -> Result<String, ServerError> {
        
        logger.info("attempting to play animation \(DataHelper.dataToHexString(data: animationId)) on \(DataHelper.dataToHexString(data: creatureId))")
       
        // Ensure the server is valid
        if let s = server {
            
            var request = Server_PlayAnimationRequest()
            request.animationID.id = animationId
            request.creatureID.id = creatureId
            
            do {
            
                // This returns a Server_PlayAnimationResponse
                let result = try await s.playAnimation(request)
    
                logger.info("successfully scheduled animation! Server said: \(result.status)")
                return .success(result.status)
    
            } catch {
                
                logger.warning("unable to play animation! Server said: \(error.localizedDescription)")
                return .failure(.otherError(error.localizedDescription))
                
            }
        }
        
        logger.error("The server is nil while attempting to play an animation remotely?")
        return .failure(.communicationError("Server is nil for some reason? 😱"))
        
    }
}

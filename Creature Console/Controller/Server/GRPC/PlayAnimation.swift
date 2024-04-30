
import Foundation
import SwiftUI
import OSLog
import GRPC


extension CreatureServerClient {
    
    
    /**
     Play an animation locally
     */
    func playAnimationLocally(animation: Animation, universe: UInt32) async -> Result<String, AnimationError> {
        // Guard against no frame data
        guard let frameData = animation.frameData else {
            logger.warning("Unable to play animation because there's no frame data to play")
            return .failure(.invalidState("🚫 Unable to play animation because there's no frame data in the animation"))
        }

        // Check for appState before entering async context
        let currentActivity = await MainActor.run { appState?.currentActivity }
        guard currentActivity == .idle else {
            logger.warning("Unable to play animation while not in idle state")
            return .failure(.invalidState("🚫 Unable to play animation while not in the idle state"))
        }
        
        // Proceed to update the appState to playingAnimation
        await MainActor.run { appState?.currentActivity = .playingAnimation }

        logger.info("Playing animation \(animation.metadata.title) on universe \(universe)")
        
        // If it has a sound file attached, let's play it
        if let url = URL(string: audioFilePath + animation.metadata.soundFile), !animation.metadata.soundFile.isEmpty {
            logger.info("Audiofile URL is \(url)")
            
            // `audioManager?.play(url:)` is an async function
            do {
                // Just call await on the play method without trying to capture a return value
                try await audioManager?.play(url: url)
                logger.info("Audio file queued up to play successfully!")
            } catch {
                logger.error("Error playing audio: \(error.localizedDescription)")
            }
        }
        
        var totalFramesPlayed: UInt32 = 0
        
        do {
            try await withThrowingTaskGroup(of: UInt32.self, returning: Void.self) { group in
                for creatureData in frameData {
                    group.addTask {
                        return try await self.streamFrameDataToCreature(creatureId: creatureData.creatureId, frameData: creatureData, universe: universe, millisecondsPerFrame: UInt64(animation.metadata.millisecondsPerFrame))
                    }
                }
                
                for try await result in group {
                    totalFramesPlayed += result
                }
            }
            
            // Log and return after all tasks complete
            logger.info("Done streaming \(totalFramesPlayed)")
            await MainActor.run {
                appState?.currentActivity = .idle
            }
            return .success("Server streamed \(totalFramesPlayed) frames")
        } catch {
            logger.error("Error occurred in a task: \(error.localizedDescription). Cancelling all tasks.")
            await MainActor.run {
                appState?.currentActivity = .idle
            }
            return .failure(.unknownError("Error occurred while playing animation: \(error.localizedDescription)"))
        }
    }


    
    
    /**
     Opens a stream to a creature and plays a set of frames to it
     */
    func streamFrameDataToCreature(creatureId: Data, frameData: FrameData, universe: UInt32, millisecondsPerFrame: UInt64) async throws -> UInt32 {
        
        guard !creatureId.isEmpty && creatureId.count == 12 else {
            logger.error("refusing to stream a set of frame data to a creature because the creatureId is invalid")
            return 0
        }
                    
        let idString = DataHelper.dataToHexString(data: creatureId)
                    
        logger.info("Streaming \(frameData.frames.count) frames to \(idString)")
        
        logger.debug("opening a connection to the server")
        
        // Use nanoseconds for precise timing
        let nanosecondsPerFrame = millisecondsPerFrame * 1_000_000
        
        // Open a connection if we can
        guard let serverStream = server?.makeStreamFramesCall() else {
            logger.error("unable to stream while playing a set of FrameData?")
            return 0
        }
        
        // Set up frame to stream
        var streamFrameData = StreamFrameData(ceatureId: creatureId, universe: universe)
        
        // Clean up
        defer {
            logger.debug("closing streaming connection")
            serverStream.requestStream.finish()
        }
        
        
        var sentFrames : UInt32 = 0
        do {
            
            // Play each frame in the dataset
            for frame in frameData.frames {
                
                // Record when we start
                let startTime = DispatchTime.now().uptimeNanoseconds
                
                // Don't go on if we've been canceled
                try Task.checkCancellation()
                
                streamFrameData.data = frame
            
                // Call out to the server
                try await serverStream.requestStream.send(streamFrameData.toServerStreamFrameData())
               
                sentFrames += 1
                
                // Sleep till we're done
                let elapsedTime = DispatchTime.now().uptimeNanoseconds - startTime
                let sleepDuration = nanosecondsPerFrame > elapsedTime ? nanosecondsPerFrame - elapsedTime : 0
                try await Task.sleep(nanoseconds: sleepDuration)
        
            }
            
        } catch is CancellationError {
            logger.info("stopping playback, we've been canceled")
        } catch {
            logger.error("error while streaming frames: \(error.localizedDescription)")
            throw ServerError.communicationError("error while streaming frames: \(error.localizedDescription)")
        }
        
        
        logger.info("done streaming \(sentFrames) frames to \(idString)")
        return sentFrames
    }
    
    
    /**
     Schedule playing an aimation on the server we're currently connected to
     */
    func playAnimationOnServer(animationId: Data, universe: UInt32) async -> Result<String, ServerError> {
        
        logger.info("attempting to play animation \(DataHelper.dataToHexString(data: animationId)) on universe \(universe)")
       
        // Ensure the server is valid
        if let s = server {
            
            var request = Server_PlayAnimationRequest()
            request.animationID.id = animationId
            request.universe = universe
            
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

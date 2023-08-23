//
//  SoundDataProcessor.swift
//  Creature Console
//
//  Created by April White on 8/22/23.
//

import Foundation
import Logging
import SwiftUI


class SoundDataProcessor : ObservableObject {
    
    @EnvironmentObject var client: CreatureServerClient
    @EnvironmentObject var appState : AppState
    
    let logger = Logger(label: "Sound Data Processor")

    
    func replaceTrackDataWithSoundData(soundData: SoundData, track: Int, animation: Animation) {
        
        logger.info("received a request to replace track \(track) with sound data from \(soundData.metadata.soundFile)")
        
        let newByteData = processSoundData(soundData: soundData, millisecondsPerFrame: animation.metadata.millisecondsPerFrame)
        animation.replaceTrackData(trackIndex: track, with: newByteData)
        
    }
    
    func processSoundData(soundData: SoundData, millisecondsPerFrame: Int32) -> [UInt8] {
        
        logger.info("sound file was: \(soundData.metadata.soundFile), duration: \(soundData.metadata.duration * 1000)ms, animationMsPerFrame: \(millisecondsPerFrame)")
        
        // How many frames are in this?
        let numberOfFrames = Int32(soundData.metadata.duration * 1000) / millisecondsPerFrame
        logger.info("this is \(numberOfFrames) frames total")
        
        var byteData = [UInt8](repeating: 0, count: Int(numberOfFrames))
        
        // soundData.cue is an array of MouthCue
        for cue in soundData.mouthCues {
     
            let startFrame = Int(cue.start * 1000) / Int(millisecondsPerFrame)
            let endFrame = Int(cue.end * 1000) / Int(millisecondsPerFrame)
            
            // Fill the array with cue.intValue from startFrame to endFrame
            byteData.replaceSubrange(startFrame..<endFrame, with: repeatElement(cue.intValue, count: endFrame - startFrame))
        }
        
        // All done!
        return byteData
        
    }
    
    
    
    
}

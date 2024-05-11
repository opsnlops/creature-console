
import Foundation
import OSLog


public class SoundDataProcessor {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundDataProcessor")

    
    public init() {
        self.logger.debug("new SoundProcessorData")
    }

    public func replaceTrackDataWithSoundData(soundData: SoundData, track: Int, animation: Animation) {

        logger.info("received a request to replace track \(track) with sound data from \(soundData.metadata.soundFile)")
        
        _ = processSoundData(soundData: soundData, millisecondsPerFrame: animation.metadata.millisecondsPerFrame)
        logger.warning("replaceTrackData() is stubbed out")
        //animation.replaceTrackData(trackIndex: track, with: newByteData)
        
    }
    
    public func processSoundData(soundData: SoundData, millisecondsPerFrame: UInt32) -> [UInt8] {

        logger.info("sound file was: \(soundData.metadata.soundFile), duration: \(soundData.metadata.duration * 1000)ms, animationMsPerFrame: \(millisecondsPerFrame)")
        
        // How many frames are in this?
        let numberOfFrames = UInt32(soundData.metadata.duration * 1000) / millisecondsPerFrame
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

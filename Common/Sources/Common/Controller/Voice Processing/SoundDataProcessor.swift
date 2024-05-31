import Foundation
import Logging

public class SoundDataProcessor {

    let logger = Logger(label: "io.opsnlops.creature-console.SoundDataProcessor")


    public init() {
        self.logger.debug("new SoundProcessorData")
    }

    public func replaceAxisDataWithSoundData(
        soundData: SoundData, axis: Int, track: Track, millisecondsPerFrame: UInt32
    ) -> Result<Track, ServerError> {
        logger.info(
            "received a request to replace track \(track)'s axis \(axis) with sound data from \(soundData.metadata.soundFile)"
        )

        let newByteData = processSoundData(
            soundData: soundData, millisecondsPerFrame: millisecondsPerFrame)

        var mutableTrack = track
        mutableTrack.replaceAxisData(axisIndex: axis, with: newByteData)

        return .success(mutableTrack)
    }

    public func processSoundData(soundData: SoundData, millisecondsPerFrame: UInt32) -> [UInt8] {

        logger.info(
            "sound file was: \(soundData.metadata.soundFile), duration: \(soundData.metadata.duration * 1000)ms, animationMsPerFrame: \(millisecondsPerFrame)"
        )

        // How many frames are in this?
        let numberOfFrames = UInt32(soundData.metadata.duration * 1000) / millisecondsPerFrame
        logger.info("this is \(numberOfFrames) frames total")

        var byteData = [UInt8](repeating: 0, count: Int(numberOfFrames))

        // soundData.cue is an array of MouthCue
        for cue in soundData.mouthCues {

            let startFrame = Int(cue.start * 1000) / Int(millisecondsPerFrame)
            let endFrame = Int(cue.end * 1000) / Int(millisecondsPerFrame)

            // Fill the array with cue.intValue from startFrame to endFrame
            byteData.replaceSubrange(
                startFrame..<endFrame,
                with: repeatElement(cue.intValue, count: endFrame - startFrame))
        }

        // All done!
        return byteData

    }

}

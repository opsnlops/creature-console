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
            "Replacing axis \(axis) on track id: \(track.id) using imported mouth data (Rhubarb JSON)."
        )

        // Validate track has frames
        guard let firstFrame = track.frames.first else {
            return .failure(.dataFormatError("Track has no frames to replace"))
        }

        // Validate axis is in bounds for this track's frame width
        let width = firstFrame.count
        guard axis >= 0 && axis < width else {
            return .failure(
                .dataFormatError("Axis index \(axis) out of bounds for frame width \(width)"))
        }

        let newByteData = processSoundData(
            soundData: soundData,
            millisecondsPerFrame: millisecondsPerFrame,
            targetFrameCount: track.frames.count
        )

        var mutableTrack = track
        mutableTrack.replaceAxisData(axisIndex: axis, with: newByteData)

        return .success(mutableTrack)
    }

    public func processSoundData(
        soundData: SoundData, millisecondsPerFrame: UInt32, targetFrameCount: Int
    ) -> [UInt8] {

        logger.info(
            "Rhubarb JSON duration: \(soundData.metadata.duration * 1000)ms, animationMsPerFrame: \(millisecondsPerFrame), targetFrameCount: \(targetFrameCount)"
        )

        var byteData = [UInt8](repeating: 0, count: targetFrameCount)

        // Map each cue's time range to frame indices, clamped to the target frame count
        for cue in soundData.mouthCues {
            let startFrame = max(
                0, min(targetFrameCount, Int((cue.start * 1000.0) / Double(millisecondsPerFrame))))
            let endFrame = max(
                startFrame,
                min(targetFrameCount, Int((cue.end * 1000.0) / Double(millisecondsPerFrame))))
            if endFrame > startFrame {
                let count = endFrame - startFrame
                byteData.replaceSubrange(
                    startFrame..<endFrame, with: repeatElement(cue.intValue, count: count))
            }
        }

        return byteData
    }

}

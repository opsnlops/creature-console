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

        // Shared bake path — see MouthShape.bakeFrames (also drives the dialog-provenance ribbon).
        let cues = soundData.mouthCues.map {
            TimedMouthValue(start: $0.start, end: $0.end, openness: $0.intValue)
        }
        return MouthShape.bakeFrames(
            cues, millisecondsPerFrame: millisecondsPerFrame, frameCount: targetFrameCount)
    }

}

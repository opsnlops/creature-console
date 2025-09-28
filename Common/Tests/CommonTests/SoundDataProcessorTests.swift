import Foundation
import Testing
@testable import Common

@Suite("SoundDataProcessor behavior")
struct SoundDataProcessorTests {

    @Test("processSoundData maps time ranges to frame indices with clamping")
    func processSoundDataMapping() throws {
        // duration 1.0s, frames at 20ms -> up to 50 frames
        let cues = [
            SoundData.MouthCue(start: 0.00, end: 0.10, value: "A"), // frames 0..5
            SoundData.MouthCue(start: 0.20, end: 0.50, value: "C"), // frames 10..25
            SoundData.MouthCue(start: 0.95, end: 1.20, value: "D")  // clamps to end
        ]
        let sound = SoundData(metadata: .init(soundFile: "a.flac", duration: 1.0), mouthCues: cues)
        let sut = SoundDataProcessor()
        let bytes = sut.processSoundData(soundData: sound, millisecondsPerFrame: 20, targetFrameCount: 50)

        // Helpers
        func range(_ r: Range<Int>) -> [UInt8] { Array(bytes[r]) }

        // Expect ranges
        #expect(range(0..<5).allSatisfy { $0 == SoundData.MouthCue(start:0,end:0,value:"A").intValue })
        #expect(range(10..<25).allSatisfy { $0 == SoundData.MouthCue(start:0,end:0,value:"C").intValue })
        // Tail end should be D up to the end (clamped)
        let dVal = SoundData.MouthCue(start:0,end:0,value:"D").intValue
        #expect(bytes.suffix(from: 47).allSatisfy { $0 == dVal })
    }

    @Test("replaceAxisDataWithSoundData validates track and axis, and replaces correctly")
    func replaceAxisDataIntegration() throws {
        // Build a small predictable track: 6 frames x width 4
        let frames: [Data] = Array(repeating: Data([0, 1, 2, 3]), count: 6)
        let track = Track(
            id: UUID(),
            creatureId: UUID().uuidString,
            animationId: UUID().uuidString,
            frames: frames
        )

        // Build sound data that maps to 6 frames at 100ms/frame
        let cues = [
            SoundData.MouthCue(start: 0.0, end: 0.3, value: "E"), // frames 0..3
            SoundData.MouthCue(start: 0.3, end: 0.6, value: "F"), // frames 3..6
        ]
        let sound = SoundData(metadata: .init(soundFile: "b.flac", duration: 0.6), mouthCues: cues)

        let sut = SoundDataProcessor()
        let result = sut.replaceAxisDataWithSoundData(
            soundData: sound,
            axis: 2,
            track: track,
            millisecondsPerFrame: 100
        )

        // Extract success value correctly
        let updated = try result.get()
        #expect(updated.frames.count == 6)

        // Axis 2 should be replaced by E..F mapping
        let eVal = SoundData.MouthCue(start: 0, end: 0, value: "E").intValue
        let fVal = SoundData.MouthCue(start: 0, end: 0, value: "F").intValue
        for (idx, frame) in updated.frames.enumerated() {
            let expected = (idx < 3) ? eVal : fVal
            #expect(frame[2] == expected)
        }

        // Other axes untouched
        #expect(updated.frames.allSatisfy { $0[0] == 0 && $0[1] == 1 && $0[3] == 3 })
    }

    @Test("replaceAxisDataWithSoundData returns failures for invalid inputs")
    func replaceAxisDataValidation() throws {
        let sut = SoundDataProcessor()

        // Empty track
        let empty = Track(id: UUID(), creatureId: UUID().uuidString, animationId: UUID().uuidString, frames: [])
        switch sut.replaceAxisDataWithSoundData(soundData: SoundData(metadata: .init(soundFile: "x", duration: 0), mouthCues: []), axis: 0, track: empty, millisecondsPerFrame: 20) {
        case .failure(let err):
            #expect(err.localizedDescription.contains("Track has no frames"))
        case .success:
            Issue.record("Expected failure for empty track")
        }

        // Out of bounds axis
        let frames: [Data] = [Data([0,0])]
        let track = Track(id: UUID(), creatureId: UUID().uuidString, animationId: UUID().uuidString, frames: frames)
        switch sut.replaceAxisDataWithSoundData(soundData: SoundData(metadata: .init(soundFile: "x", duration: 0), mouthCues: []), axis: 10, track: track, millisecondsPerFrame: 20) {
        case .failure(let err):
            #expect(err.localizedDescription.contains("out of bounds"))
        case .success:
            Issue.record("Expected failure for out-of-bounds axis")
        }
    }
}


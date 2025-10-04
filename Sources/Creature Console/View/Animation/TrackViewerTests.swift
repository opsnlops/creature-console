import Testing
import Foundation
@testable import Creature_Console
import Common

@Suite("TrackViewer extractByteStreams")
struct TrackViewerTests {

    @Test("Succeeds with consistent frame sizes")
    @MainActor
    func extractByteStreamsSuccess() {
        let frames: [Data] = [
            Data([10, 20, 30]),
            Data([40, 50, 60]),
            Data([70, 80, 90])
        ]

        let viewer = TrackViewer(
            track: Track(id: UUID(), creatureId: "c1", animationId: "a1", frames: frames),
            creature: Creature.mock(),
            inputs: []
        )

        let result = viewer.extractByteStreams(from: frames)
        switch result {
        case .success(let streams):
            #expect(streams.count == 3)
            #expect(streams[0] == [10, 40, 70])
            #expect(streams[1] == [20, 50, 80])
            #expect(streams[2] == [30, 60, 90])
        case .failure:
            Issue.record("Expected success but got failure")
        }
    }

    @Test("Fails on mismatched frame sizes")
    @MainActor
    func extractByteStreamsFailureOnMismatchedSizes() {
        let frames: [Data] = [
            Data([1, 2, 3]),
            Data([4, 5])
        ]

        let viewer = TrackViewer(
            track: Track(id: UUID(), creatureId: "c1", animationId: "a1", frames: frames),
            creature: Creature.mock(),
            inputs: []
        )

        let result = viewer.extractByteStreams(from: frames)
        switch result {
        case .success:
            Issue.record("Expected failure due to mismatched frame sizes")
        case .failure(let error):
            if case .inconsistentFrameSizes = error {
                // Success - got the expected error
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }
}

import Testing
import Foundation
@testable import Creature_Console
import Common

@Suite("TrackViewer extractByteStreams")
struct TrackViewerTests {

    @Test("Succeeds with consistent frame sizes")
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
        case .failure(let error):
            #expect(false, "Unexpected failure: \(error)")
        }
    }

    @Test("Fails on mismatched frame sizes")
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
            #expect(false, "Expected failure due to mismatched frame sizes")
        case .failure(let error):
            switch error {
            case let tvError as TrackViewer.TrackViewerError:
                switch tvError {
                case .inconsistentFrameSizes(_, _):
                    #expect(true)
                default:
                    #expect(false, "Unexpected TrackViewer error: \(tvError)")
                }
            default:
                #expect(false, "Unexpected error type: \(error)")
            }
        }
    }
}

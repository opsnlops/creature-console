import XCTest
@testable import Common
@testable import Creature_Console

final class TrackTests: XCTestCase {

    func testTrackInitialization() {
        let track = Track.mock()

        XCTAssertEqual(track.id.uuidString.count, 36)
        XCTAssertEqual(track.creatureId.count, 36)
        XCTAssertEqual(track.animationId.count, 36)
        XCTAssertEqual(track.frames.count, 8)
        XCTAssertTrue(track.frames.allSatisfy { $0.count == 7 })
    }

    func testTrackEquality() {
        let track1 = Track.mock()
        var track2 = track1

        XCTAssertEqual(track1, track2)

        track2.frames[0] = Data([1, 2, 3, 4, 5, 6, 7])
        XCTAssertNotEqual(track1, track2)
    }

    func testTrackHashing() {
        let track1 = Track.mock()
        let track2 = track1

        XCTAssertEqual(track1.hashValue, track2.hashValue)

        var hasher1 = Hasher()
        track1.hash(into: &hasher1)
        let hashValue1 = hasher1.finalize()

        var hasher2 = Hasher()
        track2.hash(into: &hasher2)
        let hashValue2 = hasher2.finalize()

        XCTAssertEqual(hashValue1, hashValue2)
    }

    func testTrackEncoding() throws {
        let track = Track.mock()
        let encoder = JSONEncoder()
        let data = try encoder.encode(track)

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["id"] as? String, track.id.uuidString.lowercased())
        XCTAssertEqual(jsonObject?["creature_id"] as? String, track.creatureId.lowercased())
        XCTAssertEqual(jsonObject?["animation_id"] as? String, track.animationId.lowercased())
        XCTAssertEqual((jsonObject?["frames"] as? [String])?.count, 8)
    }

    func testTrackDecoding() throws {
        let track = Track.mock()
        let encoder = JSONEncoder()
        let data = try encoder.encode(track)

        let decoder = JSONDecoder()
        let decodedTrack = try decoder.decode(Track.self, from: data)

        XCTAssertEqual(track, decodedTrack)
    }
}

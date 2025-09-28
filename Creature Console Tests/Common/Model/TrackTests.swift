import Foundation
import Testing
@testable import Common
@testable import Creature_Console

@Suite("Track model tests")
struct TrackTests {

    @Test
    func trackInitialization() {
        let track = Track.mock()
        #expect(track.id.uuidString.count == 36)
        #expect(track.creatureId.count == 36)
        #expect(track.animationId.count == 36)
        #expect(track.frames.count == 8)
        #expect(track.frames.allSatisfy { $0.count == 7 })
    }

    @Test
    func trackEquality() {
        let track1 = Track.mock()
        var track2 = track1
        #expect(track1 == track2)
        track2.frames[0] = Data([1, 2, 3, 4, 5, 6, 7])
        #expect(track1 != track2)
    }

    @Test
    func trackHashing() {
        let track1 = Track.mock()
        let track2 = track1
        #expect(track1.hashValue == track2.hashValue)

        var hasher1 = Hasher()
        track1.hash(into: &hasher1)
        let hashValue1 = hasher1.finalize()

        var hasher2 = Hasher()
        track2.hash(into: &hasher2)
        let hashValue2 = hasher2.finalize()
        #expect(hashValue1 == hashValue2)
    }

    @Test
    func trackEncoding() throws {
        let track = Track.mock()
        let encoder = JSONEncoder()
        let data = try encoder.encode(track)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        #expect(jsonObject != nil)
        #expect(jsonObject?["id"] as? String == track.id.uuidString.lowercased())
        #expect(jsonObject?["creature_id"] as? String == track.creatureId.lowercased())
        #expect(jsonObject?["animation_id"] as? String == track.animationId.lowercased())
        #expect((jsonObject?["frames"] as? [String])?.count == 8)
    }

    @Test
    func trackDecoding() throws {
        let track = Track.mock()
        let encoder = JSONEncoder()
        let data = try encoder.encode(track)
        let decoder = JSONDecoder()
        let decodedTrack = try decoder.decode(Track.self, from: data)
        #expect(track == decodedTrack)
    }
}

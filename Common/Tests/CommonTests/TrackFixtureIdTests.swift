import Foundation
import Testing

@testable import Common

@Suite("Track.fixtureId — backwards compatibility and new field")
struct TrackFixtureIdTests {

    @Test("legacy Track JSON without fixture_id decodes with fixtureId == nil")
    func legacyJsonHasNilFixtureId() throws {
        let json = """
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "creature_id": "abc-creature",
              "animation_id": "abc-animation",
              "frames": []
            }
            """
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        #expect(track.fixtureId == nil)
    }

    @Test("Track JSON with fixture_id decodes correctly")
    func decodesFixtureId() throws {
        let json = """
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "creature_id": "abc-creature",
              "animation_id": "abc-animation",
              "fixture_id": "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c",
              "frames": []
            }
            """
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        #expect(track.fixtureId == "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c")
    }

    @Test("encoding omits fixture_id when nil")
    func encodingOmitsFixtureIdWhenNil() throws {
        let track = Track(
            id: TrackIdentifier(),
            creatureId: UUID().uuidString.lowercased(),
            animationId: UUID().uuidString.lowercased(),
            fixtureId: nil,
            frames: []
        )
        let data = try JSONEncoder().encode(track)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["fixture_id"] == nil)
    }

    @Test("encoding includes fixture_id when set")
    func encodingIncludesFixtureIdWhenSet() throws {
        let fid = "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c"
        let track = Track(
            id: TrackIdentifier(),
            creatureId: UUID().uuidString.lowercased(),
            animationId: UUID().uuidString.lowercased(),
            fixtureId: fid,
            frames: []
        )
        let data = try JSONEncoder().encode(track)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["fixture_id"] as? String) == fid)
    }

    @Test("round-trip preserves fixtureId")
    func roundTripPreservesFixtureId() throws {
        let original = Track(
            id: TrackIdentifier(),
            creatureId: UUID().uuidString.lowercased(),
            animationId: UUID().uuidString.lowercased(),
            fixtureId: "fix-123",
            frames: [Data([1, 2, 3])]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded.fixtureId == "fix-123")
        #expect(decoded == original)
    }

    @Test("two tracks differing only by fixtureId are not equal")
    func differingFixtureIdProducesInequality() throws {
        let id = TrackIdentifier()
        let cid = UUID().uuidString.lowercased()
        let aid = UUID().uuidString.lowercased()
        let a = Track(
            id: id, creatureId: cid, animationId: aid, fixtureId: nil, frames: [])
        let b = Track(
            id: id, creatureId: cid, animationId: aid, fixtureId: "x", frames: [])
        #expect(a != b)
    }
}

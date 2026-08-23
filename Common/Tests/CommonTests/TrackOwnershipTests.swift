import Foundation
import Testing

@testable import Common

@Suite("Track ownership — exactly one of creature_id / fixture_id")
struct TrackOwnershipTests {

    private let animationId = "6f1b1e58-3a4c-4a52-9f28-9a2c1b7c4d3e"
    private let trackId = "11111111-2222-3333-4444-555555555555"
    private let creatureId = "4d2c9a10-88f3-4f2b-a5b1-2c9e0a7d1f44"
    private let fixtureId = "8e3a4b5c-1d2f-4e6a-9b0c-7f8e9d0a1b2c"

    private func json(owner: String) -> Data {
        Data(
            """
            {
              "id": "\(trackId)",
              \(owner)
              "animation_id": "\(animationId)",
              "frames": []
            }
            """.utf8)
    }

    @Test("a creature track decodes with no fixture id")
    func creatureTrackDecodes() throws {
        let track = try JSONDecoder().decode(
            Track.self, from: json(owner: "\"creature_id\": \"\(creatureId)\","))
        #expect(track.owner == .creature(creatureId))
        #expect(track.creatureId == creatureId)
        #expect(track.fixtureId == nil)
    }

    /// The server omits `creature_id` entirely for a fixture track. Before console#87 this
    /// threw, which meant a single fixture track made a whole animation undecodable.
    @Test("a fixture track decodes even though creature_id is absent")
    func fixtureTrackDecodes() throws {
        let track = try JSONDecoder().decode(
            Track.self, from: json(owner: "\"fixture_id\": \"\(fixtureId)\","))
        #expect(track.owner == .fixture(fixtureId))
        #expect(track.fixtureId == fixtureId)
        #expect(track.creatureId == nil)
    }

    @Test("a track with neither owner is rejected")
    func neitherOwnerIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Track.self, from: json(owner: ""))
        }
    }

    @Test("a track with both owners is rejected")
    func bothOwnersAreRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                Track.self,
                from: json(
                    owner: "\"creature_id\": \"\(creatureId)\", \"fixture_id\": \"\(fixtureId)\","))
        }
    }

    /// An older client wrote `creature_id: ""` alongside a real fixture id. That's the same
    /// thing as absent, and it has to stay decodable.
    @Test("an empty owner string counts as absent")
    func emptyOwnerStringIsAbsent() throws {
        let track = try JSONDecoder().decode(
            Track.self,
            from: json(owner: "\"creature_id\": \"\", \"fixture_id\": \"\(fixtureId)\","))
        #expect(track.owner == .fixture(fixtureId))
    }

    @Test("encoding a creature track omits fixture_id")
    func encodingCreatureTrackOmitsFixtureId() throws {
        let track = Track(
            id: TrackIdentifier(), creatureId: creatureId, animationId: animationId, frames: [])
        let object = try encodedObject(for: track)
        #expect(object["creature_id"] as? String == creatureId)
        #expect(object["fixture_id"] == nil)
    }

    /// The old encoder always wrote `creature_id`, so a fixture track went out as
    /// `creature_id: ""` — which the server rejects outright.
    @Test("encoding a fixture track omits creature_id entirely")
    func encodingFixtureTrackOmitsCreatureId() throws {
        let track = Track(
            id: TrackIdentifier(), fixtureId: fixtureId, animationId: animationId, frames: [])
        let object = try encodedObject(for: track)
        #expect(object["fixture_id"] as? String == fixtureId)
        #expect(object["creature_id"] == nil)
    }

    @Test("round-trip preserves the owner", arguments: [true, false])
    func roundTripPreservesOwner(isCreature: Bool) throws {
        let original =
            isCreature
            ? Track(
                id: TrackIdentifier(), creatureId: creatureId, animationId: animationId,
                frames: [Data([1, 2, 3])])
            : Track(
                id: TrackIdentifier(), fixtureId: fixtureId, animationId: animationId,
                frames: [Data([1, 2, 3])])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded == original)
        #expect(decoded.owner == original.owner)
    }

    @Test("two tracks differing only by owner are not equal")
    func differingOwnerProducesInequality() throws {
        let id = TrackIdentifier()
        let a = Track(id: id, creatureId: creatureId, animationId: animationId, frames: [])
        let b = Track(id: id, fixtureId: fixtureId, animationId: animationId, frames: [])
        #expect(a != b)
    }

    private func encodedObject(for track: Track) throws -> [String: Any] {
        let data = try JSONEncoder().encode(track)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

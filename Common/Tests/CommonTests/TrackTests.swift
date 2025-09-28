import Foundation
import Testing
@testable import Common

@Suite("Track model tests")
struct TrackTests {

    // MARK: Initialization & mock
    @Test("mock produces expected shapes and sizes")
    func mockProducesShapes() throws {
        let track = Track.mock()
        #expect(track.frames.count == 8)
        #expect(track.frames.allSatisfy { $0.count == 7 })
        #expect(!track.creatureId.isEmpty)
        #expect(!track.animationId.isEmpty)
    }

    // MARK: Equality & hashing
    @Test("value equality compares all fields including frames content")
    func equality() throws {
        let a = Track.mock()
        var b = a
        #expect(a == b)
        if !b.frames.isEmpty {
            var first = b.frames[0]
            if !first.isEmpty { first[0] = first[0] &+ 1 }
            b.frames[0] = first
            #expect(a != b)
        }
    }

    @Test("hashing matches equality semantics")
    func hashing() throws {
        let a = Track.mock()
        let b = a
        var set = Set<Track>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: Codable
    @Test("encoding uses lowercase ids and base64 frames")
    func encodingFormat() throws {
        let t = Track.mock()
        let data = try JSONEncoder().encode(t)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["id"] as? String) == t.id.uuidString.lowercased())
        #expect((object["creature_id"] as? String) == t.creatureId.lowercased())
        #expect((object["animation_id"] as? String) == t.animationId.lowercased())
        let frames = try #require(object["frames"] as? [String])
        #expect(frames.count == t.frames.count)
        // Ensure strings look like base64 (cannot reconstruct without decoding)
        #expect(frames.allSatisfy { Data(base64Encoded: $0) != nil })
    }

    @Test("Codable round-trip preserves value")
    func codableRoundTrip() throws {
        let original = Track.mock()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded == original)
    }

    // MARK: Mutation helper
    @Test("replaceAxisData mutates only the specific axis across frames")
    func replaceAxisDataMutatesCorrectAxis() throws {
        var t = Track.mock()
        try #require(!t.frames.isEmpty)
        let width = try #require(t.frames.first?.count)
        try #require(width >= 2)
        let targetAxis = 1

        // Snapshot original columns for all indices
        let originalColumns: [[UInt8]] = (0..<width).map { col in
            t.frames.map { $0[col] }
        }

        let replacement: [UInt8] = Array(repeating: 123, count: t.frames.count)
        t.replaceAxisData(axisIndex: targetAxis, with: replacement)

        // Target column should be updated to all 123s
        #expect(t.frames.map { $0[targetAxis] }.allSatisfy { $0 == 123 })

        // All other columns should be unchanged
        for col in 0..<width where col != targetAxis {
            let after = t.frames.map { $0[col] }
            #expect(after == originalColumns[col])
        }

        // Lengths unchanged
        #expect(t.frames.count == replacement.count)
    }

    @Test("replaceAxisData out-of-bounds axis is safely ignored")
    func replaceAxisDataBounds() throws {
        var t = Track.mock()
        let before = t.frames
        t.replaceAxisData(axisIndex: -1, with: [])
        t.replaceAxisData(axisIndex: (t.frames.first?.count ?? 0) + 1, with: [])
        #expect(t.frames == before)
    }
}


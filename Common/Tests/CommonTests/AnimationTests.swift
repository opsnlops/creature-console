import Foundation
import Testing

@testable import Common

@Suite("Animation core behavior")
struct AnimationTests {

    // MARK: Initialization
    @Test("default init sets up metadata, tracks, and lowercase id")
    func defaultInit() throws {
        let animation = Animation()
        #expect(animation.metadata.id == animation.id)
        #expect(animation.tracks.isEmpty)
        #expect(animation.metadata.numberOfFrames == 0)
        #expect(animation.id == animation.id.lowercased())
    }

    // MARK: Snapshot
    @Test("snapshot round-trip preserves equality")
    func snapshotRoundTrip() throws {
        let original = Animation.mock()
        let snapshot = original.snapshot()
        let reconstructed = Animation.from(snapshot: snapshot)
        #expect(original == reconstructed)
    }

    @Test("snapshot produces an independent copy of state")
    func snapshotIsIndependent() throws {
        let original = Animation.mock()
        var snapshot = original.snapshot()
        // Mutate snapshot's metadata; original should not change
        snapshot.metadata.title += " (edited)"
        #expect(original.metadata.title != snapshot.metadata.title)
    }

    // MARK: Frame count maintenance
    @Test("recalculateNumberOfFrames computes max across tracks")
    func recalculateNumberOfFrames() throws {
        let animation = Animation.mock()
        // Intentionally set an incorrect value then recompute
        animation.metadata.numberOfFrames = UInt32.max
        let expected = animation.tracks.map { UInt32($0.frames.count) }.max() ?? 0
        animation.recalculateNumberOfFrames()
        #expect(animation.metadata.numberOfFrames == expected)
    }

    @Test("tracks didSet updates numberOfFrames")
    func didSetUpdatesNumberOfFrames() throws {
        let animation = Animation.mock()
        let expected = animation.tracks.map { UInt32($0.frames.count) }.max() ?? 0
        animation.metadata.numberOfFrames = 0
        // Trigger didSet with a new array instance (even if same contents)
        animation.tracks = Array(animation.tracks)
        #expect(animation.metadata.numberOfFrames == expected)
    }

    @Test("edge cases: empty tracks yield 0 frames; mixed sizes pick max")
    func edgeCaseFrameCounts() throws {
        let a = Animation()
        #expect(a.metadata.numberOfFrames == 0)

        // Build tracks with varying frame counts
        var t1 = Track.mock()
        t1.frames.removeAll()
        var t2 = Track.mock()
        t2.frames = Array(t2.frames.prefix(1))
        var t3 = Track.mock()
        t3.frames = Array(t3.frames.prefix(7))
        a.tracks = [t1, t2, t3]
        #expect(a.metadata.numberOfFrames == 7)
    }

    // MARK: Equality & hashing
    @Test("equality and hashing are consistent")
    func equalityAndHashing() throws {
        let a = Animation.mock()
        let b = Animation.from(snapshot: a.snapshot())
        #expect(a == b)
        var set = Set<Animation>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    @Test("mutating metadata or tracks affects equality")
    func mutationsAffectEquality() throws {
        let a = Animation.mock()
        var b = Animation.from(snapshot: a.snapshot())
        #expect(a == b)

        // Change metadata
        b.metadata.title += " (different)"
        #expect(a != b)

        // Restore equality then change tracks
        b = Animation.from(snapshot: a.snapshot())
        #expect(a == b)
        if !b.tracks.isEmpty {
            var first = b.tracks[0]
            if !first.frames.isEmpty { first.frames.removeLast() }
            b.tracks[0] = first
        }
        #expect(a != b)
    }

    // MARK: Codable (encoding behavior)
    @Test("encoding lowercases id")
    func encodingLowercasesID() throws {
        let uppercaseID = UUID().uuidString.uppercased()
        let metadata = AnimationMetadata.mock()
        let animation = Animation(id: uppercaseID, metadata: metadata, tracks: [])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(animation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedID = try #require(object["id"] as? String)
        #expect(encodedID == uppercaseID.lowercased())
    }
}

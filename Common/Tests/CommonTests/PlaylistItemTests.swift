import Foundation
import Testing

@testable import Common

@Suite("PlaylistItem model tests")
struct PlaylistItemTests {

    // Real UUIDs throughout: the server requires `animation_id` to be one, and decoding
    // enforces the same rule so a bad id is caught here rather than as a 400 on save.
    private let animationId = "9c1f5d8a-4b62-4c7e-9a3d-1f0e2b8c6d54"
    private let otherAnimationId = "2b7e6f11-0c3a-4d59-8e21-5a9c4b3d7e08"

    @Test("initializes with properties")
    func initializesWithProperties() {
        let item = PlaylistItem(animationId: animationId, weight: 42)

        #expect(item.animationId == animationId)
        #expect(item.weight == 42)
        #expect(item.id == animationId)  // id should equal animationId
        #expect(item.isValid)
    }

    @Test("id property returns animationId")
    func idPropertyReturnsAnimationId() {
        let item = PlaylistItem(animationId: animationId, weight: 10)

        #expect(item.id == item.animationId)
        #expect(item.id == animationId)
    }

    @Test("encodes to JSON with snake_case")
    func encodesToJSONWithSnakeCase() throws {
        let item = PlaylistItem(animationId: animationId, weight: 75)

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["animation_id"] as? String == animationId)
        #expect(json?["weight"] as? Int == 75)
        // The server rejects unknown keys on a playlist item, so these two are the whole set.
        #expect(json?.count == 2)
    }

    @Test("decodes from JSON with snake_case")
    func decodesFromJSONWithSnakeCase() throws {
        let jsonString = """
            {
                "animation_id": "\(animationId)",
                "weight": 99
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let item = try decoder.decode(PlaylistItem.self, from: data)

        #expect(item.animationId == animationId)
        #expect(item.weight == 99)
    }

    @Test("round-trip encoding preserves data")
    func roundTripEncodingPreservesData() throws {
        let original = PlaylistItem(animationId: animationId, weight: 50)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistItem.self, from: data)

        #expect(decoded.animationId == original.animationId)
        #expect(decoded.weight == original.weight)
    }

    @Test("equality compares animationId and weight")
    func equalityComparesFields() {
        let item1 = PlaylistItem(animationId: animationId, weight: 10)
        let item2 = PlaylistItem(animationId: animationId, weight: 10)
        let item3 = PlaylistItem(animationId: otherAnimationId, weight: 10)
        let item4 = PlaylistItem(animationId: animationId, weight: 20)

        #expect(item1 == item2)
        #expect(item1 != item3)  // Different animationId
        #expect(item1 != item4)  // Different weight
    }

    @Test("hashing is consistent with equality")
    func hashingConsistentWithEquality() {
        let item1 = PlaylistItem(animationId: animationId, weight: 15)
        let item2 = PlaylistItem(animationId: animationId, weight: 15)

        var hasher1 = Hasher()
        item1.hash(into: &hasher1)

        var hasher2 = Hasher()
        item2.hash(into: &hasher2)

        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test("mock creates a valid item")
    func mockCreatesValidItem() {
        let mock = PlaylistItem.mock()

        #expect(UUID(uuidString: mock.animationId) != nil)
        #expect(PlaylistLimits.itemWeightRange.contains(mock.weight))
        #expect(mock.isValid)
    }

    // MARK: Weight bounds

    /// The accepted ends of the range. These used to be 0 and `UInt32.max`, both of which the
    /// server now rejects.
    @Test(
        "accepts the boundary weights",
        arguments: [PlaylistLimits.minimumItemWeight, 500, PlaylistLimits.maximumItemWeight])
    func acceptsBoundaryWeights(weight: UInt32) throws {
        let jsonString = """
            {
                "animation_id": "\(animationId)",
                "weight": \(weight)
            }
            """
        let decoded = try JSONDecoder().decode(
            PlaylistItem.self, from: Data(jsonString.utf8))
        #expect(decoded.weight == weight)
        #expect(decoded.isValid)
    }

    @Test("rejects weights outside the range", arguments: [0, 1000, UInt32.max])
    func rejectsOutOfRangeWeights(weight: UInt32) {
        let jsonString = """
            {
                "animation_id": "\(animationId)",
                "weight": \(weight)
            }
            """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlaylistItem.self, from: Data(jsonString.utf8))
        }
        #expect(!PlaylistItem(animationId: animationId, weight: weight).isValid)
    }

    // MARK: Identifier shape

    @Test(
        "rejects a non-UUID animation_id",
        arguments: [
            "animation-with-dashes", "animation_with_underscores", "animation.with.dots",
            "animation123", "UPPERCASE_ANIMATION", "",
        ])
    func rejectsNonUuidAnimationId(badId: String) {
        let jsonString = """
            {
                "animation_id": "\(badId)",
                "weight": 10
            }
            """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlaylistItem.self, from: Data(jsonString.utf8))
        }
        #expect(!PlaylistItem(animationId: badId, weight: 10).isValid)
    }

    /// The server compares ids as strings but accepts either case, and Foundation's `UUID`
    /// parses both — an uppercase id has to keep working.
    @Test("accepts an uppercase UUID")
    func acceptsUppercaseUuid() throws {
        let upper = animationId.uppercased()
        let jsonString = """
            {
                "animation_id": "\(upper)",
                "weight": 10
            }
            """
        let decoded = try JSONDecoder().decode(PlaylistItem.self, from: Data(jsonString.utf8))
        #expect(decoded.animationId == upper)
    }

    @Test("fails gracefully on missing fields")
    func failsGracefullyOnMissingFields() throws {
        let jsonString = """
            {
                "animation_id": "\(animationId)"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlaylistItem.self, from: data)
        }
    }
}

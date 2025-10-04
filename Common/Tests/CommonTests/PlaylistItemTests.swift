import Foundation
import Testing

@testable import Common

@Suite("PlaylistItem model tests")
struct PlaylistItemTests {

    @Test("initializes with properties")
    func initializesWithProperties() {
        let item = PlaylistItem(animationId: "anim123", weight: 42)

        #expect(item.animationId == "anim123")
        #expect(item.weight == 42)
        #expect(item.id == "anim123")  // id should equal animationId
    }

    @Test("id property returns animationId")
    func idPropertyReturnsAnimationId() {
        let item = PlaylistItem(animationId: "test_animation", weight: 10)

        #expect(item.id == item.animationId)
        #expect(item.id == "test_animation")
    }

    @Test("encodes to JSON with snake_case")
    func encodesToJSONWithSnakeCase() throws {
        let item = PlaylistItem(animationId: "anim456", weight: 75)

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["animation_id"] as? String == "anim456")
        #expect(json?["weight"] as? Int == 75)
    }

    @Test("decodes from JSON with snake_case")
    func decodesFromJSONWithSnakeCase() throws {
        let jsonString = """
            {
                "animation_id": "my_animation",
                "weight": 99
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let item = try decoder.decode(PlaylistItem.self, from: data)

        #expect(item.animationId == "my_animation")
        #expect(item.weight == 99)
    }

    @Test("round-trip encoding preserves data")
    func roundTripEncodingPreservesData() throws {
        let original = PlaylistItem(animationId: "roundtrip_test", weight: 50)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistItem.self, from: data)

        #expect(decoded.animationId == original.animationId)
        #expect(decoded.weight == original.weight)
    }

    @Test("equality compares animationId and weight")
    func equalityComparesFields() {
        let item1 = PlaylistItem(animationId: "anim1", weight: 10)
        let item2 = PlaylistItem(animationId: "anim1", weight: 10)
        let item3 = PlaylistItem(animationId: "anim2", weight: 10)
        let item4 = PlaylistItem(animationId: "anim1", weight: 20)

        #expect(item1 == item2)
        #expect(item1 != item3)  // Different animationId
        #expect(item1 != item4)  // Different weight
    }

    @Test("hashing is consistent with equality")
    func hashingConsistentWithEquality() {
        let item1 = PlaylistItem(animationId: "same", weight: 15)
        let item2 = PlaylistItem(animationId: "same", weight: 15)

        var hasher1 = Hasher()
        item1.hash(into: &hasher1)

        var hasher2 = Hasher()
        item2.hash(into: &hasher2)

        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test("mock creates valid item")
    func mockCreatesValidItem() {
        let mock = PlaylistItem.mock()

        #expect(!mock.animationId.isEmpty)
        #expect(mock.weight < 100)  // Mock uses random 0-99
    }

    @Test("handles zero weight")
    func handlesZeroWeight() throws {
        let item = PlaylistItem(animationId: "zero_weight", weight: 0)

        #expect(item.weight == 0)

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistItem.self, from: data)

        #expect(decoded.weight == 0)
    }

    @Test("handles maximum UInt32 weight")
    func handlesMaxWeight() throws {
        let maxWeight: UInt32 = UInt32.max
        let item = PlaylistItem(animationId: "max_weight", weight: maxWeight)

        #expect(item.weight == maxWeight)

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistItem.self, from: data)

        #expect(decoded.weight == maxWeight)
    }

    @Test("handles special characters in animationId")
    func handlesSpecialCharactersInId() throws {
        let specialIds = [
            "animation-with-dashes",
            "animation_with_underscores",
            "animation.with.dots",
            "animation123",
            "UPPERCASE_ANIMATION",
        ]

        for specialId in specialIds {
            let item = PlaylistItem(animationId: specialId, weight: 10)

            let encoder = JSONEncoder()
            let data = try encoder.encode(item)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PlaylistItem.self, from: data)

            #expect(decoded.animationId == specialId)
        }
    }

    @Test("fails gracefully on missing fields")
    func failsGracefullyOnMissingFields() throws {
        let jsonString = """
            {
                "animation_id": "test"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlaylistItem.self, from: data)
        }
    }
}

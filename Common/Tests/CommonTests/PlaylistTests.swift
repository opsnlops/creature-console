import Foundation
import Testing

@testable import Common

@Suite("Playlist model tests")
struct PlaylistTests {

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let items = [
            PlaylistItem(animationId: "anim1", weight: 10),
            PlaylistItem(animationId: "anim2", weight: 20),
        ]
        let playlist = Playlist(id: "playlist123", name: "Test Playlist", items: items)

        #expect(playlist.id == "playlist123")
        #expect(playlist.name == "Test Playlist")
        #expect(playlist.items.count == 2)
        #expect(playlist.numberOfItems == 2)
    }

    @Test("numberOfItems computed property is correct")
    func numberOfItemsIsCorrect() {
        let emptyPlaylist = Playlist(id: "empty", name: "Empty", items: [])
        #expect(emptyPlaylist.numberOfItems == 0)

        let items = (0..<5).map { PlaylistItem(animationId: "anim\($0)", weight: UInt32($0)) }
        let playlist = Playlist(id: "test", name: "Test", items: items)
        #expect(playlist.numberOfItems == 5)
    }

    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let items = [
            PlaylistItem(animationId: "anim1", weight: 10)
        ]
        let playlist = Playlist(id: "playlist123", name: "Test", items: items)

        let encoder = JSONEncoder()
        let data = try encoder.encode(playlist)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["id"] as? String == "playlist123")
        #expect(json?["name"] as? String == "Test")
        #expect(json?["number_of_items"] as? Int == 1)
        #expect((json?["items"] as? [[String: Any]])?.count == 1)
    }

    @Test("decodes from JSON correctly")
    func decodesFromJSON() throws {
        let jsonString = """
            {
                "id": "playlist456",
                "name": "My Playlist",
                "items": [
                    {
                        "animation_id": "anim1",
                        "weight": 5
                    },
                    {
                        "animation_id": "anim2",
                        "weight": 10
                    }
                ]
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let playlist = try decoder.decode(Playlist.self, from: data)

        #expect(playlist.id == "playlist456")
        #expect(playlist.name == "My Playlist")
        #expect(playlist.items.count == 2)
        #expect(playlist.items[0].animationId == "anim1")
        #expect(playlist.items[0].weight == 5)
        #expect(playlist.items[1].animationId == "anim2")
        #expect(playlist.items[1].weight == 10)
    }

    @Test("round-trip encoding preserves data")
    func roundTripEncodingPreservesData() throws {
        let items = [
            PlaylistItem(animationId: "anim1", weight: 15),
            PlaylistItem(animationId: "anim2", weight: 25),
            PlaylistItem(animationId: "anim3", weight: 35),
        ]
        let original = Playlist(id: "test123", name: "Round Trip Test", items: items)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.items.count == original.items.count)
        #expect(decoded.numberOfItems == original.numberOfItems)
    }

    @Test("equality compares all fields")
    func equalityComparesAllFields() {
        let items1 = [PlaylistItem(animationId: "anim1", weight: 10)]
        let items2 = [PlaylistItem(animationId: "anim1", weight: 10)]
        let items3 = [PlaylistItem(animationId: "anim2", weight: 20)]

        let playlist1 = Playlist(id: "same", name: "Same", items: items1)
        let playlist2 = Playlist(id: "same", name: "Same", items: items2)
        let playlist3 = Playlist(id: "same", name: "Different", items: items1)
        let playlist4 = Playlist(id: "different", name: "Same", items: items1)
        let playlist5 = Playlist(id: "same", name: "Same", items: items3)

        #expect(playlist1 == playlist2)
        #expect(playlist1 != playlist3)  // Different name
        #expect(playlist1 != playlist4)  // Different ID
        #expect(playlist1 != playlist5)  // Different items
    }

    @Test("hashing is consistent with equality")
    func hashingConsistentWithEquality() {
        let items = [PlaylistItem(animationId: "anim1", weight: 10)]

        let playlist1 = Playlist(id: "same", name: "Same", items: items)
        let playlist2 = Playlist(id: "same", name: "Same", items: items)

        var hasher1 = Hasher()
        playlist1.hash(into: &hasher1)

        var hasher2 = Hasher()
        playlist2.hash(into: &hasher2)

        // Equal objects should have equal hashes
        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test("mock creates valid playlist")
    func mockCreatesValidPlaylist() {
        let mock = Playlist.mock()

        #expect(!mock.id.isEmpty)
        #expect(mock.name == "Mock Playlist")
        #expect(mock.items.count == 2)
        #expect(mock.numberOfItems == 2)
    }

    @Test("handles empty items array")
    func handlesEmptyItemsArray() throws {
        let playlist = Playlist(id: "empty", name: "Empty Playlist", items: [])

        #expect(playlist.numberOfItems == 0)

        let encoder = JSONEncoder()
        let data = try encoder.encode(playlist)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        #expect(decoded.items.isEmpty)
        #expect(decoded.numberOfItems == 0)
    }

    @Test("handles large number of items")
    func handlesLargeNumberOfItems() {
        let items = (0..<1000).map { PlaylistItem(animationId: "anim\($0)", weight: UInt32($0)) }
        let playlist = Playlist(id: "large", name: "Large Playlist", items: items)

        #expect(playlist.numberOfItems == 1000)
        #expect(playlist.items.count == 1000)
    }
}

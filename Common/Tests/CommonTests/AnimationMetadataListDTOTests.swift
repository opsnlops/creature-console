import Foundation
import Testing

@testable import Common

@Suite("AnimationMetadataListDTO JSON encoding and decoding")
struct AnimationMetadataListDTOTests {

    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let metadata1 = AnimationMetadata(
            id: "anim1",
            title: "Wave",
            lastUpdated: Date(timeIntervalSince1970: 1_000_000),
            millisecondsPerFrame: 20,
            note: "Test animation",
            soundFile: "wave.mp3",
            numberOfFrames: 100,
            multitrackAudio: false
        )

        let dto = AnimationMetadataListDTO(count: 1, items: [metadata1])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["count"] as? Int == 1)
        #expect((json?["items"] as? [[String: Any]])?.count == 1)
    }

    @Test("decodes from JSON correctly")
    func decodesFromJSON() throws {
        let jsonString = """
            {
                "count": 2,
                "items": [
                    {
                        "animation_id": "anim1",
                        "title": "Wave",
                        "last_updated": "1970-01-12T13:46:40Z",
                        "milliseconds_per_frame": 20,
                        "note": "Test note",
                        "sound_file": "wave.mp3",
                        "number_of_frames": 100,
                        "multitrack_audio": false
                    },
                    {
                        "animation_id": "anim2",
                        "title": "Nod",
                        "last_updated": "1970-01-12T13:46:40Z",
                        "milliseconds_per_frame": 30,
                        "note": "",
                        "sound_file": "",
                        "number_of_frames": 50,
                        "multitrack_audio": true
                    }
                ]
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(AnimationMetadataListDTO.self, from: data)

        #expect(dto.count == 2)
        #expect(dto.items.count == 2)
        #expect(dto.items[0].title == "Wave")
        #expect(dto.items[1].title == "Nod")
        #expect(dto.items[1].multitrackAudio == true)
    }

    @Test("round-trip encoding preserves data")
    func roundTripPreservesData() throws {
        let metadata1 = AnimationMetadata(
            id: "anim1",
            title: "Test",
            lastUpdated: Date(timeIntervalSince1970: 1_000_000),
            millisecondsPerFrame: 20,
            note: "Note",
            soundFile: "test.mp3",
            numberOfFrames: 100,
            multitrackAudio: false
        )

        let original = AnimationMetadataListDTO(count: 1, items: [metadata1])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AnimationMetadataListDTO.self, from: data)

        #expect(decoded.count == original.count)
        #expect(decoded.items.count == original.items.count)
        #expect(decoded.items[0].id == original.items[0].id)
        #expect(decoded.items[0].title == original.items[0].title)
    }

    @Test("handles empty items array")
    func handlesEmptyItems() throws {
        let dto = AnimationMetadataListDTO(count: 0, items: [])

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnimationMetadataListDTO.self, from: data)

        #expect(decoded.count == 0)
        #expect(decoded.items.isEmpty)
    }

    @Test("handles mismatched count and items")
    func handlesMismatchedCount() throws {
        // This is a data integrity test - the server might send count != items.count
        let jsonString = """
            {
                "count": 5,
                "items": [
                    {
                        "animation_id": "anim1",
                        "title": "Wave",
                        "last_updated": "1970-01-12T13:46:40Z",
                        "milliseconds_per_frame": 20,
                        "note": "",
                        "sound_file": "",
                        "number_of_frames": 100,
                        "multitrack_audio": false
                    }
                ]
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(AnimationMetadataListDTO.self, from: data)

        // Should decode successfully even if count doesn't match
        #expect(dto.count == 5)
        #expect(dto.items.count == 1)
    }

    @Test("fails gracefully on missing count")
    func failsOnMissingCount() throws {
        let jsonString = """
            {
                "items": []
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(AnimationMetadataListDTO.self, from: data)
        }
    }

    @Test("fails gracefully on missing items")
    func failsOnMissingItems() throws {
        let jsonString = """
            {
                "count": 0
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(AnimationMetadataListDTO.self, from: data)
        }
    }
}

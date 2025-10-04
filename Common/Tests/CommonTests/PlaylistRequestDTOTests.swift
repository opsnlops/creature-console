import Foundation
import Testing

@testable import Common

@Suite("PlaylistRequestDTO JSON encoding and decoding")
struct PlaylistRequestDTOTests {

    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let dto = PlaylistRequestDTO(
            playlist_id: "playlist_123",
            universe: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["playlist_id"] as? String == "playlist_123")
        #expect(json?["universe"] as? Int == 1)
    }

    @Test("decodes from JSON correctly")
    func decodesFromJSON() throws {
        let jsonString = """
            {
                "playlist_id": "morning_routine",
                "universe": 3
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dto = try decoder.decode(PlaylistRequestDTO.self, from: data)

        #expect(dto.playlist_id == "morning_routine")
        #expect(dto.universe == 3)
    }

    @Test("round-trip encoding preserves data")
    func roundTripPreservesData() throws {
        let original = PlaylistRequestDTO(
            playlist_id: "test_playlist",
            universe: 7
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistRequestDTO.self, from: data)

        #expect(decoded.playlist_id == original.playlist_id)
        #expect(decoded.universe == original.universe)
    }

    @Test("handles various playlist IDs")
    func handlesVariousPlaylistIDs() throws {
        let playlistIDs = [
            "simple",
            "with-dashes",
            "with_underscores",
            "with.dots",
            "MixedCase123",
        ]

        for playlistID in playlistIDs {
            let dto = PlaylistRequestDTO(playlist_id: playlistID, universe: 1)

            let encoder = JSONEncoder()
            let data = try encoder.encode(dto)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PlaylistRequestDTO.self, from: data)

            #expect(decoded.playlist_id == playlistID)
        }
    }

    @Test("fails gracefully on missing playlist_id")
    func failsOnMissingPlaylistID() throws {
        let jsonString = """
            {
                "universe": 1
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlaylistRequestDTO.self, from: data)
        }
    }

    @Test("fails gracefully on missing universe")
    func failsOnMissingUniverse() throws {
        let jsonString = """
            {
                "playlist_id": "test"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlaylistRequestDTO.self, from: data)
        }
    }
}

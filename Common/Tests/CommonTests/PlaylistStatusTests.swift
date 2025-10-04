import Foundation
import Testing

@testable import Common

@Suite("PlaylistStatus model tests")
struct PlaylistStatusTests {

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let status = PlaylistStatus(
            universe: 1,
            playlist: "playlist123",
            playing: true,
            currentAnimation: "anim456"
        )

        #expect(status.universe == 1)
        #expect(status.playlist == "playlist123")
        #expect(status.playing == true)
        #expect(status.currentAnimation == "anim456")
    }

    @Test("encodes to JSON with snake_case for current_animation")
    func encodesToJSONWithSnakeCase() throws {
        let status = PlaylistStatus(
            universe: 2,
            playlist: "test_playlist",
            playing: false,
            currentAnimation: "current_anim"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(status)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["universe"] as? Int == 2)
        #expect(json?["playlist"] as? String == "test_playlist")
        #expect(json?["playing"] as? Bool == false)
        #expect(json?["current_animation"] as? String == "current_anim")
    }

    @Test("decodes from JSON with snake_case")
    func decodesFromJSONWithSnakeCase() throws {
        let jsonString = """
            {
                "universe": 3,
                "playlist": "my_playlist",
                "playing": true,
                "current_animation": "my_anim"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let status = try decoder.decode(PlaylistStatus.self, from: data)

        #expect(status.universe == 3)
        #expect(status.playlist == "my_playlist")
        #expect(status.playing == true)
        #expect(status.currentAnimation == "my_anim")
    }

    @Test("round-trip encoding preserves data")
    func roundTripEncodingPreservesData() throws {
        let original = PlaylistStatus(
            universe: 5,
            playlist: "roundtrip_playlist",
            playing: true,
            currentAnimation: "roundtrip_anim"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistStatus.self, from: data)

        #expect(decoded.universe == original.universe)
        #expect(decoded.playlist == original.playlist)
        #expect(decoded.playing == original.playing)
        #expect(decoded.currentAnimation == original.currentAnimation)
    }

    @Test("equality compares all fields")
    func equalityComparesAllFields() {
        let status1 = PlaylistStatus(universe: 1, playlist: "p1", playing: true, currentAnimation: "a1")
        let status2 = PlaylistStatus(universe: 1, playlist: "p1", playing: true, currentAnimation: "a1")
        let status3 = PlaylistStatus(universe: 2, playlist: "p1", playing: true, currentAnimation: "a1")
        let status4 = PlaylistStatus(universe: 1, playlist: "p2", playing: true, currentAnimation: "a1")
        let status5 = PlaylistStatus(universe: 1, playlist: "p1", playing: false, currentAnimation: "a1")
        let status6 = PlaylistStatus(universe: 1, playlist: "p1", playing: true, currentAnimation: "a2")

        #expect(status1 == status2)
        #expect(status1 != status3)  // Different universe
        #expect(status1 != status4)  // Different playlist
        #expect(status1 != status5)  // Different playing
        #expect(status1 != status6)  // Different currentAnimation
    }

    @Test("hashing is consistent with equality")
    func hashingConsistentWithEquality() {
        let status1 = PlaylistStatus(universe: 1, playlist: "test", playing: true, currentAnimation: "anim")
        let status2 = PlaylistStatus(universe: 1, playlist: "test", playing: true, currentAnimation: "anim")

        var hasher1 = Hasher()
        status1.hash(into: &hasher1)

        var hasher2 = Hasher()
        status2.hash(into: &hasher2)

        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test("mock creates valid status")
    func mockCreatesValidStatus() {
        let mock = PlaylistStatus.mock()

        #expect(mock.universe >= 1 && mock.universe <= 999)
        #expect(!mock.playlist.isEmpty)
        #expect(mock.playing == false)
        #expect(!mock.currentAnimation.isEmpty)
    }

    @Test("handles playing true and false")
    func handlesPlayingStates() throws {
        let playingTrue = PlaylistStatus(universe: 1, playlist: "p", playing: true, currentAnimation: "a")
        let playingFalse = PlaylistStatus(universe: 1, playlist: "p", playing: false, currentAnimation: "a")

        let encoder = JSONEncoder()

        let dataTrue = try encoder.encode(playingTrue)
        let decodedTrue = try JSONDecoder().decode(PlaylistStatus.self, from: dataTrue)
        #expect(decodedTrue.playing == true)

        let dataFalse = try encoder.encode(playingFalse)
        let decodedFalse = try JSONDecoder().decode(PlaylistStatus.self, from: dataFalse)
        #expect(decodedFalse.playing == false)
    }

    @Test("handles various universe values")
    func handlesVariousUniverseValues() throws {
        let universes = [0, 1, 100, 999, Int.max]

        for universe in universes {
            let status = PlaylistStatus(
                universe: universe,
                playlist: "test",
                playing: false,
                currentAnimation: "anim"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(status)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PlaylistStatus.self, from: data)

            #expect(decoded.universe == universe)
        }
    }

    @Test("handles empty strings for IDs")
    func handlesEmptyStrings() throws {
        let status = PlaylistStatus(
            universe: 1,
            playlist: "",
            playing: false,
            currentAnimation: ""
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(status)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlaylistStatus.self, from: data)

        #expect(decoded.playlist == "")
        #expect(decoded.currentAnimation == "")
    }

    @Test("handles special characters in IDs")
    func handlesSpecialCharactersInIDs() throws {
        let specialIds = [
            "playlist-with-dashes",
            "playlist_with_underscores",
            "playlist.with.dots",
            "UPPERCASE_PLAYLIST",
        ]

        for playlistId in specialIds {
            let status = PlaylistStatus(
                universe: 1,
                playlist: playlistId,
                playing: false,
                currentAnimation: "anim"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(status)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PlaylistStatus.self, from: data)

            #expect(decoded.playlist == playlistId)
        }
    }

    @Test("fails gracefully on missing required fields")
    func failsGracefullyOnMissingFields() throws {
        let jsonString = """
            {
                "universe": 1,
                "playlist": "test"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlaylistStatus.self, from: data)
        }
    }
}

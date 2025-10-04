import Foundation
import Testing

@testable import Common

@Suite("PlayAnimationRequestDto JSON encoding and decoding")
struct PlayAnimationRequestDtoTests {

    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let dto = PlayAnimationRequestDto(
            animation_id: "animation_123",
            universe: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["animation_id"] as? String == "animation_123")
        #expect(json?["universe"] as? Int == 1)
    }

    @Test("decodes from JSON correctly")
    func decodesFromJSON() throws {
        let jsonString = """
            {
                "animation_id": "wave_hand",
                "universe": 2
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dto = try decoder.decode(PlayAnimationRequestDto.self, from: data)

        #expect(dto.animation_id == "wave_hand")
        #expect(dto.universe == 2)
    }

    @Test("round-trip encoding preserves data")
    func roundTripPreservesData() throws {
        let original = PlayAnimationRequestDto(
            animation_id: "test_animation",
            universe: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlayAnimationRequestDto.self, from: data)

        #expect(decoded.animation_id == original.animation_id)
        #expect(decoded.universe == original.universe)
    }

    @Test("handles various universe IDs")
    func handlesVariousUniverseIDs() throws {
        let universes: [UniverseIdentifier] = [0, 1, 10, 100, 999]

        for universe in universes {
            let dto = PlayAnimationRequestDto(
                animation_id: "test",
                universe: universe
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(dto)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PlayAnimationRequestDto.self, from: data)

            #expect(decoded.universe == universe)
        }
    }

    @Test("handles special characters in animation_id")
    func handlesSpecialCharactersInID() throws {
        let dto = PlayAnimationRequestDto(
            animation_id: "animation-with_special.chars123",
            universe: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlayAnimationRequestDto.self, from: data)

        #expect(decoded.animation_id == dto.animation_id)
    }

    @Test("fails gracefully on missing animation_id")
    func failsOnMissingAnimationID() throws {
        let jsonString = """
            {
                "universe": 1
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlayAnimationRequestDto.self, from: data)
        }
    }

    @Test("fails gracefully on missing universe")
    func failsOnMissingUniverse() throws {
        let jsonString = """
            {
                "animation_id": "test"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlayAnimationRequestDto.self, from: data)
        }
    }

    @Test("fails gracefully on wrong type for universe")
    func failsOnWrongTypeForUniverse() throws {
        let jsonString = """
            {
                "animation_id": "test",
                "universe": "one"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(PlayAnimationRequestDto.self, from: data)
        }
    }
}

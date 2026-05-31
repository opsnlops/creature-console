import Foundation
import Testing

@testable import Common

@Suite("StoryboardListDTO decoding")
struct StoryboardListDTOTests {

    @Test("decodes count and items")
    func decodesList() throws {
        let json = """
            {
              "count": 2,
              "items": [
                { "id": "11111111-1111-1111-1111-111111111111", "title": "One", "notes": "",
                  "tiles": [], "created_at": 1, "updated_at": 2 },
                { "id": "22222222-2222-2222-2222-222222222222", "title": "Two", "notes": "",
                  "tiles": [], "created_at": 3, "updated_at": 4 }
              ]
            }
            """
        let dto = try JSONDecoder().decode(StoryboardListDTO.self, from: Data(json.utf8))
        #expect(dto.count == 2)
        #expect(dto.items.count == 2)
        #expect(dto.items.first?.title == "One")
    }

    @Test("decodes an empty list")
    func decodesEmpty() throws {
        let json = #"{ "count": 0, "items": [] }"#
        let dto = try JSONDecoder().decode(StoryboardListDTO.self, from: Data(json.utf8))
        #expect(dto.count == 0)
        #expect(dto.items.isEmpty)
    }

    @Test("fails when a required key is missing")
    func failsOnMissingKey() {
        let json = #"{ "items": [] }"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StoryboardListDTO.self, from: Data(json.utf8))
        }
    }
}

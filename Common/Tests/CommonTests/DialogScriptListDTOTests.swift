import Foundation
import Testing

@testable import Common

@Suite("DialogScriptListDTO decoding")
struct DialogScriptListDTOTests {

    @Test("decodes count and items")
    func decodesList() throws {
        let json = """
            {
              "count": 2,
              "items": [
                { "id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2", "title": "One", "notes": "", "turns": [], "created_at": 1, "updated_at": 2 },
                { "id": "b9262b22-f6fe-4918-8a2a-f9ba7b4c49d2", "title": "Two", "notes": "", "turns": [], "created_at": 3, "updated_at": 4 }
              ]
            }
            """
        let dto = try JSONDecoder().decode(DialogScriptListDTO.self, from: Data(json.utf8))
        #expect(dto.count == 2)
        #expect(dto.items.count == 2)
        #expect(dto.items.first?.title == "One")
    }

    @Test("decodes an empty list")
    func decodesEmpty() throws {
        let json = #"{ "count": 0, "items": [] }"#
        let dto = try JSONDecoder().decode(DialogScriptListDTO.self, from: Data(json.utf8))
        #expect(dto.count == 0)
        #expect(dto.items.isEmpty)
    }

    @Test("fails when a required key is missing")
    func failsOnMissingKey() {
        let json = #"{ "items": [] }"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DialogScriptListDTO.self, from: Data(json.utf8))
        }
    }
}

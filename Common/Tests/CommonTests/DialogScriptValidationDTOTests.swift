import Foundation
import Testing

@testable import Common

@Suite("DialogScriptValidationDTO decoding")
struct DialogScriptValidationDTOTests {

    @Test("decodes an invalid result with hard errors")
    func decodesInvalid() throws {
        let json = """
            {
              "valid": false,
              "script_id": "",
              "turn_count": 1,
              "missing_creature_ids": [],
              "error_messages": ["turn creature_id is not a UUID: 'not-a-uuid'"]
            }
            """
        let dto = try JSONDecoder().decode(
            DialogScriptValidationDTO.self, from: Data(json.utf8))
        #expect(dto.valid == false)
        #expect(dto.scriptId == "")
        #expect(dto.turnCount == 1)
        #expect(dto.errorMessages.count == 1)
        #expect(dto.missingCreatureIds.isEmpty)
    }

    @Test("decodes a valid result with a soft creature warning")
    func decodesValidWithWarning() throws {
        let json = """
            {
              "valid": true,
              "script_id": "a9262b22-f6fe-4918-8a2a-f9ba7b4c49d2",
              "turn_count": 6,
              "missing_creature_ids": ["bad-creature-id-here"],
              "error_messages": []
            }
            """
        let dto = try JSONDecoder().decode(
            DialogScriptValidationDTO.self, from: Data(json.utf8))
        #expect(dto.valid == true)
        #expect(dto.turnCount == 6)
        #expect(dto.missingCreatureIds == ["bad-creature-id-here"])
        #expect(dto.errorMessages.isEmpty)
    }

    @Test("tolerates missing optional arrays")
    func toleratesMissingArrays() throws {
        let json = #"{ "valid": true, "turn_count": 0 }"#
        let dto = try JSONDecoder().decode(
            DialogScriptValidationDTO.self, from: Data(json.utf8))
        #expect(dto.valid == true)
        #expect(dto.missingCreatureIds.isEmpty)
        #expect(dto.errorMessages.isEmpty)
    }
}

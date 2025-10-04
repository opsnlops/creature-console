import Foundation
import Testing

@testable import Common

@Suite("StatusDTO JSON encoding and decoding")
struct StatusDTOTests {

    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let dto = StatusDTO(status: "OK", code: 200, message: "Success")

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["status"] as? String == "OK")
        #expect(json?["code"] as? Int == 200)
        #expect(json?["message"] as? String == "Success")
    }

    @Test("decodes from JSON correctly")
    func decodesFromJSON() throws {
        let jsonString = """
            {
                "status": "ERROR",
                "code": 500,
                "message": "Internal server error"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dto = try decoder.decode(StatusDTO.self, from: data)

        #expect(dto.status == "ERROR")
        #expect(dto.code == 500)
        #expect(dto.message == "Internal server error")
    }

    @Test("round-trip encoding preserves data")
    func roundTripPreservesData() throws {
        let original = StatusDTO(status: "WARNING", code: 418, message: "I'm a teapot")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StatusDTO.self, from: data)

        #expect(decoded.status == original.status)
        #expect(decoded.code == original.code)
        #expect(decoded.message == original.message)
    }

    @Test("handles empty message")
    func handlesEmptyMessage() throws {
        let dto = StatusDTO(status: "OK", code: 204, message: "")

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StatusDTO.self, from: data)

        #expect(decoded.message == "")
    }

    @Test("handles special characters in message")
    func handlesSpecialCharacters() throws {
        let dto = StatusDTO(
            status: "ERROR",
            code: 400,
            message: "Invalid input: \"name\" must not contain <>&"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StatusDTO.self, from: data)

        #expect(decoded.message == dto.message)
    }

    @Test("handles various HTTP status codes")
    func handlesVariousStatusCodes() throws {
        let testCases: [(String, UInt16, String)] = [
            ("OK", 200, "Success"),
            ("CREATED", 201, "Resource created"),
            ("BAD_REQUEST", 400, "Bad request"),
            ("UNAUTHORIZED", 401, "Unauthorized"),
            ("NOT_FOUND", 404, "Not found"),
            ("SERVER_ERROR", 500, "Internal error"),
        ]

        for (status, code, message) in testCases {
            let dto = StatusDTO(status: status, code: code, message: message)

            let encoder = JSONEncoder()
            let data = try encoder.encode(dto)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(StatusDTO.self, from: data)

            #expect(decoded.status == status)
            #expect(decoded.code == code)
            #expect(decoded.message == message)
        }
    }

    @Test("fails gracefully on missing required fields")
    func failsOnMissingFields() throws {
        let jsonString = """
            {
                "status": "OK"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(StatusDTO.self, from: data)
        }
    }

    @Test("fails gracefully on wrong type for code")
    func failsOnWrongTypeForCode() throws {
        let jsonString = """
            {
                "status": "OK",
                "code": "two hundred",
                "message": "Success"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(StatusDTO.self, from: data)
        }
    }
}

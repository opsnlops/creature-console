import Foundation
import Testing

@testable import Common

@Suite("StatusDTO JSON encoding and decoding")
struct StatusDTOTests {

    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let dto = StatusDTO(status: "OK", code: 200, message: "Success", sessionId: nil)

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
        let dto = StatusDTO(status: "OK", code: 204, message: "", sessionId: nil)

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
            message: "Invalid input: \"name\" must not contain <>&",
            sessionId: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StatusDTO.self, from: data)

        #expect(decoded.message == dto.message)
    }

    @Test("handles various HTTP status codes")
    func handlesVariousStatusCodes() throws {
        let testCases: [(String, UInt16, String, String?)] = [
            ("OK", 200, "Success", nil),
            ("CREATED", 201, "Resource created", "session-1"),
            ("BAD_REQUEST", 400, "Bad request", nil),
            ("UNAUTHORIZED", 401, "Unauthorized", "session-2"),
            ("NOT_FOUND", 404, "Not found", nil),
            ("SERVER_ERROR", 500, "Internal error", nil),
        ]

        for (status, code, message, sessionId) in testCases {
            let dto = StatusDTO(status: status, code: code, message: message, sessionId: sessionId)

            let encoder = JSONEncoder()
            let data = try encoder.encode(dto)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(StatusDTO.self, from: data)

            #expect(decoded.status == status)
            #expect(decoded.code == code)
            #expect(decoded.message == message)
            #expect(decoded.sessionId == sessionId)
        }
    }

    @Test("decodes session id when present")
    func decodesSessionId() throws {
        let jsonString = """
            {
                "status": "OK",
                "code": 200,
                "message": "Scheduled",
                "session_id": "uuid-123"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dto = try decoder.decode(StatusDTO.self, from: data)

        #expect(dto.sessionId == "uuid-123")
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

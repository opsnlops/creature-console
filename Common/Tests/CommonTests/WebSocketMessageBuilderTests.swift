import Foundation
import Testing

@testable import Common

@Suite("WebSocketMessageBuilder tests")
struct WebSocketMessageBuilderTests {

    struct SimplePayload: Codable {
        let message: String
        let value: Int
    }

    struct DatePayload: Codable {
        let timestamp: Date
        let event: String
    }

    @Test("creates message with simple payload")
    func createsMessageWithSimplePayload() throws {
        let payload = SimplePayload(message: "test", value: 42)
        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .notice,
            payload: payload
        )

        #expect(jsonString.contains("\"command\":\"notice\""))
        #expect(jsonString.contains("\"message\":\"test\""))
        #expect(jsonString.contains("\"value\":42"))
    }

    @Test("creates valid JSON structure")
    func createsValidJSONStructure() throws {
        let payload = SimplePayload(message: "hello", value: 123)
        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .logging,
            payload: payload
        )

        // Parse the JSON to verify structure
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["command"] as? String == "log")
        let payloadJson = json?["payload"] as? [String: Any]
        #expect(payloadJson?["message"] as? String == "hello")
        #expect(payloadJson?["value"] as? Int == 123)
    }

    @Test("uses ISO8601 date encoding")
    func usesISO8601DateEncoding() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let payload = DatePayload(timestamp: date, event: "test_event")

        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .streamFrame,
            payload: payload
        )

        // Should contain ISO8601 formatted date
        #expect(jsonString.contains("1970-01-12T13:46:40Z"))
        #expect(jsonString.contains("\"event\":\"test_event\""))
    }

    @Test("handles different message types")
    func handlesDifferentMessageTypes() throws {
        let payload = SimplePayload(message: "test", value: 1)

        let messageTypes: [ServerMessageType] = [
            .serverCounters,
            .logging,
            .notice,
            .statusLights,
            .streamFrame,
            .motorSensorReport,
            .boardSensorReport,
            .cacheInvalidation,
            .playlistStatus,
            .emergencyStop,
            .watchdogWarning,
        ]

        for type in messageTypes {
            let jsonString = try WebSocketMessageBuilder.createMessage(type: type, payload: payload)
            #expect(jsonString.contains("\"command\":\"\(type.rawValue)\""))
        }
    }

    @Test("encoding errors are propagated")
    func encodingErrorsArePropagated() throws {
        struct NonEncodablePayload: Codable {
            let data: Data

            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    data,
                    EncodingError.Context(
                        codingPath: [],
                        debugDescription: "Cannot encode"
                    )
                )
            }
        }

        let payload = NonEncodablePayload(data: Data())

        // Should throw an encoding error
        #expect(throws: Error.self) {
            try WebSocketMessageBuilder.createMessage(
                type: .notice,
                payload: payload
            )
        }
    }

    @Test("handles empty payload")
    func handlesEmptyPayload() throws {
        struct EmptyPayload: Codable {}

        let payload = EmptyPayload()
        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .notice,
            payload: payload
        )

        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["command"] as? String == "notice")
        let payloadJson = json?["payload"] as? [String: Any]
        #expect(payloadJson?.isEmpty == true)
    }

    @Test("handles complex nested payload")
    func handlesComplexNestedPayload() throws {
        struct NestedPayload: Codable {
            struct Inner: Codable {
                let id: String
                let values: [Int]
            }
            let outer: String
            let inner: Inner
        }

        let payload = NestedPayload(
            outer: "test",
            inner: NestedPayload.Inner(id: "inner123", values: [1, 2, 3])
        )

        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .notice,
            payload: payload
        )

        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let payloadJson = json?["payload"] as? [String: Any]
        #expect(payloadJson?["outer"] as? String == "test")

        let innerJson = payloadJson?["inner"] as? [String: Any]
        #expect(innerJson?["id"] as? String == "inner123")
        #expect((innerJson?["values"] as? [Int])?.count == 3)
    }

    @Test("handles special characters in payload")
    func handlesSpecialCharactersInPayload() throws {
        let payload = SimplePayload(
            message: "Special: \"quotes\", \n newlines, \t tabs",
            value: 999
        )

        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .notice,
            payload: payload
        )

        // Should properly escape special characters
        #expect(jsonString.contains("\\\"quotes\\\""))
        #expect(jsonString.contains("\\n"))
        #expect(jsonString.contains("\\t"))

        // Should be valid JSON
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
    }

    @Test("creates valid JSON with command and payload")
    func createsValidJSONWithCommandAndPayload() throws {
        let payload = SimplePayload(message: "test", value: 42)
        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .notice,
            payload: payload
        )

        // Parse and verify structure (not using WebSocketMessageDTO since it has custom decoding)
        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["command"] as? String == "notice")

        let payloadJson = json?["payload"] as? [String: Any]
        #expect(payloadJson?["message"] as? String == "test")
        #expect(payloadJson?["value"] as? Int == 42)
    }

    @Test("handles array payload")
    func handlesArrayPayload() throws {
        let payload = [1, 2, 3, 4, 5]
        let jsonString = try WebSocketMessageBuilder.createMessage(
            type: .serverCounters,
            payload: payload
        )

        let data = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["command"] as? String == "server-counters")
        let arrayPayload = json?["payload"] as? [Int]
        #expect(arrayPayload == [1, 2, 3, 4, 5])
    }

    @Test("handles optional values in payload")
    func handlesOptionalValuesInPayload() throws {
        struct OptionalPayload: Codable {
            let required: String
            let optional: String?
        }

        let withOptional = OptionalPayload(required: "req", optional: "opt")
        let jsonWith = try WebSocketMessageBuilder.createMessage(type: .notice, payload: withOptional)
        #expect(jsonWith.contains("\"optional\":\"opt\""))

        let withoutOptional = OptionalPayload(required: "req", optional: nil)
        let jsonWithout = try WebSocketMessageBuilder.createMessage(
            type: .notice,
            payload: withoutOptional
        )
        // nil values are typically omitted in JSON encoding
        #expect(!jsonWithout.contains("optional") || jsonWithout.contains("\"optional\":null"))
    }
}

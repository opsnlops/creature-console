import Foundation
import Testing

@testable import Common

@Suite("ServerError detailed message extraction")
struct ServerErrorDetailedMessageTests {

    @Test("detailedMessage extracts ServerError message")
    func detailedMessageExtractsServerError() {
        let error: Error = ServerError.communicationError("Network timeout")
        let message = ServerError.detailedMessage(from: error)
        #expect(message == "Network timeout")
    }

    @Test("detailedMessage handles all ServerError types")
    func detailedMessageHandlesAllTypes() {
        let errors: [(ServerError, String)] = [
            (.communicationError("Comm error"), "Comm error"),
            (.dataFormatError("Format error"), "Format error"),
            (.otherError("Other error"), "Other error"),
            (.databaseError("DB error"), "DB error"),
            (.notFound("Not found"), "Not found"),
            (.unknownError("Unknown"), "Unknown"),
            (.serverError("Server error"), "Server error"),
            (.websocketError("WS error"), "WS error"),
            (.notImplemented("Not impl"), "Not impl"),
        ]

        for (error, expectedMessage) in errors {
            let message = ServerError.detailedMessage(from: error)
            #expect(message == expectedMessage)
        }
    }

    @Test("detailedMessage falls back to localizedDescription for non-ServerError")
    func detailedMessageFallsBackToLocalizedDescription() {
        struct CustomError: Error, LocalizedError {
            var errorDescription: String? { "Custom error message" }
        }

        let error: Error = CustomError()
        let message = ServerError.detailedMessage(from: error)
        #expect(message == "Custom error message")
    }

    @Test("detailedMessage handles NSError")
    func detailedMessageHandlesNSError() {
        let nsError = NSError(
            domain: "TestDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "NSError description"]
        )
        let message = ServerError.detailedMessage(from: nsError)
        #expect(message == "NSError description")
    }

    @Test("detailedMessage preserves detailed server messages")
    func detailedMessagePreservesDetailedMessages() {
        let detailedMessage =
            "Playlist 'My Playlist' started successfully on universe 1 - estimated duration 5m 32s"
        let error: Error = ServerError.otherError(detailedMessage)
        let extracted = ServerError.detailedMessage(from: error)
        #expect(extracted == detailedMessage)
    }

    @Test("ServerError conforms to LocalizedError")
    func serverErrorConformsToLocalizedError() {
        let error = ServerError.notFound("Resource not found")
        #expect(error.errorDescription == "Resource not found")
        #expect(error.localizedDescription == "Resource not found")
    }

    @Test("ServerError cases are Equatable by message")
    func serverErrorCasesAreEquatable() {
        let error1 = ServerError.communicationError("Same message")
        let error2 = ServerError.communicationError("Same message")
        let error3 = ServerError.communicationError("Different message")

        // Swift enums with associated values aren't automatically Equatable
        // but we can test the messages are extracted correctly
        #expect(error1.errorDescription == error2.errorDescription)
        #expect(error1.errorDescription != error3.errorDescription)
    }
}

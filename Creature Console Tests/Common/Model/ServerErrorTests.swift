import XCTest
@testable import Common
@testable import Creature_Console

final class ServerErrorTests: XCTestCase {

    func testCommunicationErrorDescription() {
        let message = "Failed to communicate with server."
        let error = ServerError.communicationError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testDataFormatErrorDescription() {
        let message = "Data format is incorrect."
        let error = ServerError.dataFormatError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testOtherErrorDescription() {
        let message = "An unspecified error occurred."
        let error = ServerError.otherError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testDatabaseErrorDescription() {
        let message = "Database query failed."
        let error = ServerError.databaseError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testNotFoundErrorDescription() {
        let message = "Requested resource not found."
        let error = ServerError.notFound(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testUnknownErrorDescription() {
        let message = "An unknown error occurred."
        let error = ServerError.unknownError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testServerErrorDescription() {
        let message = "Internal server error."
        let error = ServerError.serverError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testWebsocketErrorDescription() {
        let message = "Websocket connection failed."
        let error = ServerError.websocketError(message)
        XCTAssertEqual(error.localizedDescription, message)
    }

    func testNotImplementedErrorDescription() {
        let message = "Feature not implemented."
        let error = ServerError.notImplemented(message)
        XCTAssertEqual(error.localizedDescription, message)
    }
}

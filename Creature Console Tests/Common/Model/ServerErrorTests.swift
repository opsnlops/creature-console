import Testing

@testable import Common
@testable import Creature_Console

@Suite("ServerError localized descriptions")
struct ServerErrorTests {

    @Test("communicationError has correct description")
    func communicationErrorDescription() {
        let message = "Failed to communicate with server."
        let error = ServerError.communicationError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("dataFormatError has correct description")
    func dataFormatErrorDescription() {
        let message = "Data format is incorrect."
        let error = ServerError.dataFormatError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("otherError has correct description")
    func otherErrorDescription() {
        let message = "An unspecified error occurred."
        let error = ServerError.otherError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("databaseError has correct description")
    func databaseErrorDescription() {
        let message = "Database query failed."
        let error = ServerError.databaseError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("notFound has correct description")
    func notFoundErrorDescription() {
        let message = "Requested resource not found."
        let error = ServerError.notFound(message)
        #expect(error.localizedDescription == message)
    }

    @Test("unknownError has correct description")
    func unknownErrorDescription() {
        let message = "An unknown error occurred."
        let error = ServerError.unknownError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("serverError has correct description")
    func serverErrorDescription() {
        let message = "Internal server error."
        let error = ServerError.serverError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("websocketError has correct description")
    func websocketErrorDescription() {
        let message = "Websocket connection failed."
        let error = ServerError.websocketError(message)
        #expect(error.localizedDescription == message)
    }

    @Test("notImplemented has correct description")
    func notImplementedErrorDescription() {
        let message = "Feature not implemented."
        let error = ServerError.notImplemented(message)
        #expect(error.localizedDescription == message)
    }
}

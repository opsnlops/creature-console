import MongoKitten
import Testing

@testable import creature_world

@Suite("Creature World MongoDB startup diagnostics")
struct MongoWorldStartupTests {
    @Test("Connection diagnostics identify targets without exposing credentials")
    func connectionDiagnosticsAreSafe() throws {
        let uri =
            "mongodb://beaky:very-secret@mongo-a:27018,mongo-b:27019/creature_world?ssl=true"
        let details = MongoWorldConnectionDetails(settings: try ConnectionSettings(uri))

        #expect(details.targets == "mongo-a:27018,mongo-b:27019")
        #expect(details.database == "creature_world")
        #expect(details.usesTLS)
        #expect(!details.logMetadata.description.contains("beaky"))
        #expect(!details.logMetadata.description.contains("very-secret"))
    }

    @Test("Connection failures explain how to fix configuration")
    func connectionFailureIsActionable() throws {
        let error = MongoWorldStartupError.connectionFailed(
            targets: "127.0.0.1:27017",
            database: "creature_world",
            reason: "Connection refused"
        )
        let description = try #require(error.errorDescription)

        #expect(description.contains("127.0.0.1:27017"))
        #expect(description.contains("creature_world"))
        #expect(description.contains("Connection refused"))
        #expect(description.contains("MONGODB_URI"))
        #expect(description.contains("--mongodb-uri"))
    }
}

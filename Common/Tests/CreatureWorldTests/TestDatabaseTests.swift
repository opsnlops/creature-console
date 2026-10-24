import Foundation
import Testing

@testable import creature_world

/// The test run's own database (#247): the URI keeps its server and options, and only an old
/// run's database is ever recognized as one.
@Suite("Each test run's own database")
struct TestDatabaseTests {
    @Test("The database is replaced, the server and the options kept")
    func replacesTheDatabase() {
        #expect(
            TestDatabase.replacingDatabase(
                in:
                    "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true",
                with: "creature_world_test_1_a")
                == "mongodb://127.0.0.1:27017/creature_world_test_1_a?replicaSet=creature-world&directConnection=true"
        )
        #expect(
            TestDatabase.replacingDatabase(
                in: "mongodb://user:pw@a:1,b:2/creature_world", with: "creature_world_test_1_a")
                == "mongodb://user:pw@a:1,b:2/creature_world_test_1_a")
        #expect(
            TestDatabase.replacingDatabase(
                in: "mongodb://127.0.0.1:27017?directConnection=true",
                with: "creature_world_test_1_a")
                == "mongodb://127.0.0.1:27017/creature_world_test_1_a?directConnection=true")
        #expect(
            TestDatabase.replacingDatabase(in: "mongodb://127.0.0.1:27017", with: "x")
                == "mongodb://127.0.0.1:27017/x")
    }

    @Test("A run's database tells when it was made; no other database does")
    func madeAtComesFromTheName() {
        #expect(
            TestDatabase.madeAt("creature_world_test_1792810000_ab12cd")
                == Date(timeIntervalSince1970: 1_792_810_000))
        #expect(TestDatabase.madeAt("creature_world") == nil)
        #expect(TestDatabase.madeAt("creature_world_test_") == nil)
        #expect(TestDatabase.madeAt("admin") == nil)
    }

    @Test("Under MONGODB_TEST_URI, the run's database is its own and the World accepts it")
    func runsDatabaseIsItsOwn() throws {
        guard let uri = TestDatabase.uri else { return }
        let name = try #require(
            uri.split(separator: "/").last?.split(separator: "?").first.map(String.init))
        #expect(name.hasPrefix(CreatureWorldConfiguration.testDatabasePrefix))
        #expect(CreatureWorldConfiguration.isWorldDatabase(name))
        #expect(try CreatureWorldConfiguration(mongoURI: uri).mongoURI == uri)
    }
}

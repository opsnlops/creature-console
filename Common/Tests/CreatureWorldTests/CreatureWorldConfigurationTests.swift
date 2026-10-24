import Foundation
import Testing

@testable import creature_world

@Suite("Creature World configuration")
struct CreatureWorldConfigurationTests {
    @Test("Defaults bind only to loopback")
    func defaultsBindToLoopback() throws {
        let configuration = try CreatureWorldConfiguration.load(from: nil, environment: [:])

        #expect(configuration.host == "127.0.0.1")
        #expect(configuration.mongoURI == CreatureWorldConfiguration.defaultMongoURI)
        #expect(configuration.port == 8001)
    }

    @Test("House asks are the word rule's unless the config gives them to the mind (#240)")
    func houseAsks() throws {
        #expect(
            try CreatureWorldConfiguration.load(from: nil, environment: [:]).houseAsks == .words)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("world-house-asks-\(UUID().uuidString).json")
        try Data(#"{"house_asks": "mind"}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let loaded = try CreatureWorldConfiguration.load(from: file, environment: [:])
        #expect(loaded.houseAsks == .mind)
        #expect(try loaded.overriding(host: nil, port: nil).houseAsks == .mind)
    }

    @Test("The packaged config loads, with the bird deciding house asks (#240)")
    func packagedConfigurationLoads() throws {
        let packaged = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("debian/creature-world.json")
        let loaded = try CreatureWorldConfiguration.load(from: packaged, environment: [:])
        #expect(loaded.houseAsks == .mind)
    }

    @Test("JSON configuration loads and command values override it")
    func configurationLoadsAndOverrides() throws {
        let loaded = try CreatureWorldConfiguration.load(from: fixtureURL, environment: [:])
        let overridden = try loaded.overriding(host: "::1", port: 18_091)
        let expectedLoaded = try CreatureWorldConfiguration(
            host: "127.0.0.1",
            port: 18_090,
            mongoURI: "mongodb://mongo.example:27017/creature_world?replicaSet=world"
        )
        let expectedOverridden = try CreatureWorldConfiguration(
            host: "::1",
            port: 18_091,
            mongoURI: expectedLoaded.mongoURI
        )

        #expect(loaded == expectedLoaded)
        #expect(overridden == expectedOverridden)
    }

    @Test("Server environment variables override JSON configuration")
    func environmentOverridesConfiguration() throws {
        let loaded = try CreatureWorldConfiguration.load(
            from: fixtureURL,
            environment: [
                CreatureWorldConfiguration.hostEnvironmentKey: "0.0.0.0",
                CreatureWorldConfiguration.allowedOriginsEnvironmentKey:
                    "https://viewer.example, https://communicator.example",
                CreatureWorldConfiguration.mongoURIEnvironmentKey:
                    "mongodb://mongo.internal:27017/creature_world",
                CreatureWorldConfiguration.portEnvironmentKey: "18092",
            ]
        )

        #expect(loaded.host == "0.0.0.0")
        #expect(
            loaded.allowedOrigins == [
                "https://viewer.example", "https://communicator.example",
            ]
        )
        #expect(loaded.mongoURI == "mongodb://mongo.internal:27017/creature_world")
        #expect(loaded.port == 18_092)
    }

    @Test("Configuration requires the isolated creature_world database")
    func rejectsAnotherDatabase() {
        #expect(
            throws: CreatureWorldConfigurationError.unexpectedMongoDatabase(
                expected: "creature_world",
                actual: "creature_server"
            )
        ) {
            try CreatureWorldConfiguration(
                mongoURI: "mongodb://127.0.0.1:27017/creature_server"
            )
        }
    }

    @Test("A test run's own database is the World's too; a lookalike is not (#247)")
    func acceptsATestRunsDatabase() throws {
        let run = try CreatureWorldConfiguration(
            mongoURI: "mongodb://127.0.0.1:27017/creature_world_test_1792810000_ab12cd")
        #expect(run.mongoURI.hasSuffix("creature_world_test_1792810000_ab12cd"))
        #expect(CreatureWorldConfiguration.isWorldDatabase("creature_world"))
        #expect(!CreatureWorldConfiguration.isWorldDatabase("creature_world_test_"))
        #expect(!CreatureWorldConfiguration.isWorldDatabase("creature_worlds"))
        #expect(!CreatureWorldConfiguration.isWorldDatabase(nil))
        #expect(throws: CreatureWorldConfigurationError.self) {
            try CreatureWorldConfiguration(mongoURI: "mongodb://127.0.0.1:27017/creature_world_x")
        }
    }

    @Test("Invalid server port environment variable fails clearly")
    func invalidEnvironmentPortFailsClearly() {
        #expect(
            throws: CreatureWorldConfigurationError.invalidEnvironmentValue(
                name: CreatureWorldConfiguration.portEnvironmentKey,
                value: "bird"
            )
        ) {
            try CreatureWorldConfiguration.load(
                from: nil,
                environment: [CreatureWorldConfiguration.portEnvironmentKey: "bird"]
            )
        }
    }

    @Test("Configuration rejects empty hosts and invalid ports")
    func invalidConfigurationFailsClearly() {
        #expect(throws: CreatureWorldConfigurationError.emptyHost) {
            try CreatureWorldConfiguration(host: "  ")
        }
        #expect(throws: CreatureWorldConfigurationError.invalidPort(0)) {
            try CreatureWorldConfiguration(port: 0)
        }
        #expect(throws: CreatureWorldConfigurationError.invalidPort(65_536)) {
            try CreatureWorldConfiguration(port: 65_536)
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CreatureWorld/creature-world.json")
    }
}

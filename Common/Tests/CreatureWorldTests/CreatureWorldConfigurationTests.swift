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
        #expect(configuration.port == 8000)
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
                CreatureWorldConfiguration.apiTokenEnvironmentKey: "test-token",
                CreatureWorldConfiguration.allowedOriginsEnvironmentKey:
                    "https://viewer.example, https://communicator.example",
                CreatureWorldConfiguration.mongoURIEnvironmentKey:
                    "mongodb://mongo.internal:27017/creature_world",
                CreatureWorldConfiguration.portEnvironmentKey: "18092",
            ]
        )

        #expect(loaded.host == "0.0.0.0")
        #expect(loaded.apiToken == "test-token")
        #expect(
            loaded.allowedOrigins == [
                "https://viewer.example", "https://communicator.example",
            ]
        )
        #expect(loaded.mongoURI == "mongodb://mongo.internal:27017/creature_world")
        #expect(loaded.port == 18_092)
    }

    @Test("Non-loopback binding requires API authentication")
    func nonLoopbackRequiresAPIToken() {
        #expect(
            throws: CreatureWorldConfigurationError.missingAPIToken(host: "0.0.0.0")
        ) {
            try CreatureWorldConfiguration.load(
                from: nil,
                environment: [CreatureWorldConfiguration.hostEnvironmentKey: "0.0.0.0"]
            )
        }
    }

    @Test("API token cannot be blank")
    func blankAPITokenIsRejected() {
        #expect(throws: CreatureWorldConfigurationError.emptyAPIToken) {
            try CreatureWorldConfiguration(apiToken: "  ")
        }
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

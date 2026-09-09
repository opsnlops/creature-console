import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import Testing

@testable import creature_world

@Suite("Creature World application")
struct CreatureWorldApplicationTests {
    @Test("GET health returns build and schema versions")
    func healthEndpoint() async throws {
        let application = try makeApplication()

        try await application.test(.router) { client in
            try await client.execute(uri: "/world/v1/health", method: .get) { response in
                #expect(response.status == .ok)
                let health = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                #expect(health.status == "ok")
                #expect(health.service == "creature-world")
                #expect(health.buildVersion == "application-test")
                #expect(health.mongodb == "ok")
                #expect(health.schemaVersion == 9)
            }
        }
    }

    @Test("Unknown and unprefixed routes return not found")
    func unknownAndUnprefixedRoutes() async throws {
        let application = try makeApplication()

        try await application.test(.router) { client in
            try await client.execute(uri: "/missing", method: .get) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("GET health returns service unavailable when MongoDB is unavailable")
    func unavailableHealthEndpoint() async throws {
        let application = try makeApplication(readinessCheck: { false })

        try await application.test(.router) { client in
            try await client.execute(uri: "/world/v1/health", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                let health = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                #expect(health.status == "unavailable")
                #expect(health.mongodb == "unavailable")
            }
        }
    }

    private func makeApplication(
        readinessCheck: @escaping @Sendable () async -> Bool = { true }
    ) throws -> Application<RouterResponder<BasicRequestContext>> {
        let configuration = try CreatureWorldConfiguration(host: "127.0.0.1", port: 8080)
        let dependencies = CreatureWorldDependencies.testing(
            configuration: configuration,
            logger: Logger(label: "creature-world-tests"),
            buildInfo: CreatureWorldBuildInfo(version: "application-test", schemaVersion: 9),
            readinessCheck: readinessCheck
        )
        return makeCreatureWorldApplication(dependencies: dependencies)
    }
}

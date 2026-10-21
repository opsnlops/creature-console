import Foundation
import Testing

@testable import creature_world

@Suite("Creature World health")
struct HealthServiceTests {
    @Test("Health reports service, build, schema, and migration versions")
    func reportsVersions() async throws {
        let buildInfo = CreatureWorldBuildInfo(
            version: "test-build", schemaVersion: 42, migrationVersion: 15)
        let service = HealthService(buildInfo: buildInfo)

        #expect(
            await service.response()
                == HealthResponse(
                    status: "ok",
                    service: "creature-world",
                    buildVersion: "test-build",
                    mongodb: "ok",
                    schemaVersion: 42,
                    migrationVersion: 15
                )
        )
        #expect(
            CreatureWorldBuildInfo.current.migrationVersion == MongoWorldMigrator.currentVersion)

        let object = try #require(
            JSONSerialization.jsonObject(with: try await service.encodedResponse())
                as? [String: Any]
        )
        #expect(object["status"] as? String == "ok")
        #expect(object["service"] as? String == "creature-world")
        #expect(object["build_version"] as? String == "test-build")
        #expect(object["mongodb"] as? String == "ok")
        #expect(object["schema_version"] as? Int == 42)
        #expect(object["migration_version"] as? Int == 15)
    }

    @Test("Health reports MongoDB unavailability")
    func reportsMongoDBUnavailability() async {
        let buildInfo = CreatureWorldBuildInfo(version: "test-build", schemaVersion: 42)
        let service = HealthService(buildInfo: buildInfo, readinessCheck: { false })

        let response = await service.response()
        #expect(response.status == "unavailable")
        #expect(response.mongodb == "unavailable")
        // Not ready, the migration the database holds is not known.
        #expect(response.migrationVersion == nil)
    }

    @Test("A World older than 0.62.0 says no migration, and still reads")
    func olderWorldsStillRead() throws {
        let health = try JSONDecoder().decode(
            HealthResponse.self,
            from: Data(
                #"{"service":"creature-world","build_version":"0.61.0","status":"ok","mongodb":"ok","schema_version":1}"#
                    .utf8))
        #expect(health.schemaVersion == 1)
        #expect(health.migrationVersion == nil)
    }
}

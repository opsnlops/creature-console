import Foundation
import Testing

@testable import creature_world

@Suite("Creature World health")
struct HealthServiceTests {
    @Test("Health reports service, build, and schema versions")
    func reportsVersions() async throws {
        let buildInfo = CreatureWorldBuildInfo(version: "test-build", schemaVersion: 42)
        let service = HealthService(buildInfo: buildInfo)

        #expect(
            await service.response()
                == HealthResponse(
                    status: "ok",
                    service: "creature-world",
                    buildVersion: "test-build",
                    mongodb: "ok",
                    schemaVersion: 42
                )
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: try await service.encodedResponse())
                as? [String: Any]
        )
        #expect(object["status"] as? String == "ok")
        #expect(object["service"] as? String == "creature-world")
        #expect(object["build_version"] as? String == "test-build")
        #expect(object["mongodb"] as? String == "ok")
        #expect(object["schema_version"] as? Int == 42)
    }

    @Test("Health reports MongoDB unavailability")
    func reportsMongoDBUnavailability() async {
        let buildInfo = CreatureWorldBuildInfo(version: "test-build", schemaVersion: 42)
        let service = HealthService(buildInfo: buildInfo, readinessCheck: { false })

        let response = await service.response()
        #expect(response.status == "unavailable")
        #expect(response.mongodb == "unavailable")
    }
}

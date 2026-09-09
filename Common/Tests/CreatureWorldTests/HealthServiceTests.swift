import Foundation
import Testing

@testable import creature_world

@Suite("Creature World health")
struct HealthServiceTests {
    @Test("Health reports service, build, and schema versions")
    func reportsVersions() throws {
        let buildInfo = CreatureWorldBuildInfo(version: "test-build", schemaVersion: 42)
        let service = HealthService(buildInfo: buildInfo)

        #expect(
            service.response()
                == HealthResponse(
                    status: "ok",
                    service: "creature-world",
                    buildVersion: "test-build",
                    schemaVersion: 42
                )
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: service.encodedResponse()) as? [String: Any]
        )
        #expect(object["status"] as? String == "ok")
        #expect(object["service"] as? String == "creature-world")
        #expect(object["build_version"] as? String == "test-build")
        #expect(object["schema_version"] as? Int == 42)
    }
}

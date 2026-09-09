import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let service: String
    let buildVersion: String
    let schemaVersion: Int

    private enum CodingKeys: String, CodingKey {
        case status
        case service
        case buildVersion = "build_version"
        case schemaVersion = "schema_version"
    }
}

struct HealthService: Sendable {
    private let buildInfo: CreatureWorldBuildInfo

    init(buildInfo: CreatureWorldBuildInfo) {
        self.buildInfo = buildInfo
    }

    func response() -> HealthResponse {
        HealthResponse(
            status: "ok",
            service: "creature-world",
            buildVersion: buildInfo.version,
            schemaVersion: buildInfo.schemaVersion
        )
    }

    func encodedResponse() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response())
    }
}

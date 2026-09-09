import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let service: String
    let buildVersion: String
    let mongodb: String
    let schemaVersion: Int

    private enum CodingKeys: String, CodingKey {
        case status
        case service
        case buildVersion = "build_version"
        case mongodb
        case schemaVersion = "schema_version"
    }
}

struct HealthService: Sendable {
    private let buildInfo: CreatureWorldBuildInfo
    private let readinessCheck: @Sendable () async -> Bool

    init(
        buildInfo: CreatureWorldBuildInfo,
        readinessCheck: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.buildInfo = buildInfo
        self.readinessCheck = readinessCheck
    }

    func response() async -> HealthResponse {
        let isReady = await readinessCheck()
        return HealthResponse(
            status: isReady ? "ok" : "unavailable",
            service: "creature-world",
            buildVersion: buildInfo.version,
            mongodb: isReady ? "ok" : "unavailable",
            schemaVersion: buildInfo.schemaVersion
        )
    }

    func encodedResponse() async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try await encoder.encode(response())
    }
}

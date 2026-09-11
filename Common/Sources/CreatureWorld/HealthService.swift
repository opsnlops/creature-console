import Foundation
import WorldCore

typealias HealthResponse = WorldHealth

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

import WorldCore

struct CreatureWorldBuildInfo: Codable, Equatable, Sendable {
    static let current = CreatureWorldBuildInfo(
        version: "0.1.11",
        schemaVersion: WorldSchema.currentVersion
    )

    let version: String
    let schemaVersion: Int

    private enum CodingKeys: String, CodingKey {
        case version = "build_version"
        case schemaVersion = "schema_version"
    }
}

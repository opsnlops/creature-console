import WorldCore

struct CreatureWorldBuildInfo: Codable, Equatable, Sendable {
    static let current = CreatureWorldBuildInfo(
        version: "0.64.5",
        schemaVersion: WorldSchema.currentVersion
    )

    let version: String
    let schemaVersion: Int
    /// The database migration this build runs to at startup.
    let migrationVersion: Int

    init(
        version: String, schemaVersion: Int,
        migrationVersion: Int = MongoWorldMigrator.currentVersion
    ) {
        self.version = version
        self.schemaVersion = schemaVersion
        self.migrationVersion = migrationVersion
    }

    private enum CodingKeys: String, CodingKey {
        case version = "build_version"
        case schemaVersion = "schema_version"
        case migrationVersion = "migration_version"
    }
}

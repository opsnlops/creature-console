import Common
import Foundation
import OSLog
import SwiftData

@ModelActor
actor DmxFixtureImporter {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DmxFixtureImporter")

    /// Upsert a batch of DmxFixture DTOs. Idempotent — safe to call repeatedly with
    /// overlapping data.
    func upsertBatch(_ dtos: [Common.DmxFixture]) async throws {
        guard !dtos.isEmpty else { return }

        let allExistingDescriptor = FetchDescriptor<DmxFixtureModel>()
        let allExisting = try modelContext.fetch(allExistingDescriptor)
        let existingByID = Dictionary(uniqueKeysWithValues: allExisting.map { ($0.id, $0) })

        let encoder = JSONEncoder()

        try modelContext.transaction {
            for dto in dtos {
                let channelsJSON = (try? encoder.encode(dto.channels)) ?? Data("[]".utf8)
                let patternsJSON = (try? encoder.encode(dto.patterns)) ?? Data("[]".utf8)
                let bindingsJSON = (try? encoder.encode(dto.bindings)) ?? Data("[]".utf8)

                if let existing = existingByID[dto.id] {
                    existing.name = dto.name
                    existing.typeRaw = dto.type.rawValue
                    existing.channelOffset = Int(dto.channelOffset)
                    existing.assignedUniverse = dto.assignedUniverse.map { Int($0) }
                    existing.channelsJSON = channelsJSON
                    existing.patternsJSON = patternsJSON
                    existing.bindingsJSON = bindingsJSON
                } else {
                    modelContext.insert(DmxFixtureModel(dto: dto))
                }
            }
        }
        logger.debug("Upserted batch of \(dtos.count) DMX fixtures into SwiftData")
    }

    /// Remove fixtures not present in the provided set of ids. Used by the
    /// cache-invalidation rebuild path to drop entries that no longer exist on the
    /// server.
    func deleteAllExcept(ids: Set<String>) async throws {
        let descriptor = FetchDescriptor<DmxFixtureModel>()
        let all = try modelContext.fetch(descriptor)
        if all.isEmpty { return }
        try modelContext.transaction {
            for model in all where !ids.contains(model.id) {
                modelContext.delete(model)
            }
        }
        logger.debug("Deleted DMX fixtures not in provided id set; kept \(ids.count)")
    }
}
